// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract SportChain {
    struct Participante {
        bytes32 hashIdentidad; // Huella digital de sus datos (fuera de la cadena)
        bool registrado; // Flag para validar si existe en la plataforma
    }

    struct Evento {
        uint256 costoInscripcion; // Costo en wei para asegurar cupo
        bool finalizado; // Estado de la competencia
        address[3] podio; // Espacio acotado para los 3 ganadores (Push)
    }

    address public owner;

    // Listado de Jueces autorizados por el Admin (Dirección => Permitido)
    mapping(address => bool) public esJuez;

    // Listado global de participantes registrados por su dirección pública
    mapping(address => Participante) public participantes;

    // Registro histórico de eventos creados (ID del evento => Detalle del Evento)
    mapping(uint256 => Evento) public eventos;

    // Control individual para saber quién pagó en qué evento (Evento ID => Participante => Pagó)
    mapping(uint256 => mapping(address => bool)) public inscritosAEvento;

    // Control para evitar que alguien retire su reembolso dos veces
    mapping(uint256 => mapping(address => bool)) public reembolsoReclamado;

    // Contador global para generar los IDs de eventos secuenciales
    uint256 public totalEventos;

    // Errores customizados
    error NoEsAdmin(address usuario);
    error NoEsJuezAutorizado(address usuario);
    error ParticipanteYaRegistrado();
    error ParticipanteNoRegistrado();
    error EventoNoExiste();
    error InsuficienteETH(uint256 enviado, uint256 requerido);
    error YaInscrito();
    error EventoYaFinalizado();
    error EventoNoFinalizado();
    error YaReclamoMedalla();
    error NoParticipoEnEvento();
    error ReembolsoYaReclamado();
    error TransferenciaFallida();

    // Eventos
    event OwnerCambiado(address indexed antiguoOwner, address indexed nuevoOwner);
    event AccesoJuezModificado(address indexed juez, bool autorizado);
    event ParticipanteRegistrado(address indexed participante, bytes32 hashIdentidad);
    event EventoCreado(uint256 indexed eventoId, uint256 costoInscripcion);
    event InscripcionExitosa(uint256 indexed eventoId, address indexed participante);
    event EventoFinalizado(uint256 indexed eventoId, address[3] podio);
    event MedallaGeneralReclamada(uint256 indexed eventoId, address indexed participante);
    event ReembolsoEmitido(uint256 indexed eventoId, address indexed participante, uint256 monto);

    // MODIFICADORES (CONTROL DE ACCESO)
    // Restringe funciones críticas únicamente al Administrador principal
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NoEsAdmin(msg.sender);
        }
        _;
    }

    // Restringe funciones operativas únicamente a Jueces incluidos en la lista blanca
    modifier onlyJudge() {
        if (!esJuez[msg.sender]) {
            revert NoEsJuezAutorizado(msg.sender);
        }
        _;
    }

    constructor(address _juez1, address _juez2) {
        // Quien hace el deploy (tú) queda registrado como el único Admin Supremo
        owner = msg.sender;
        emit OwnerCambiado(address(0), msg.sender);

        // Autorización jueces
        esJuez[_juez1] = true;
        esJuez[_juez2] = true;
        emit AccesoJuezModificado(_juez1, true);
        emit AccesoJuezModificado(_juez2, true);
    }

    // Funciones solo del owner

    /**
     * @notice Permite al Admin agregar nuevos jueces o revocar accesos en el futuro.
     * @param _juez Dirección de la billetera a modificar.
     * @param _autorizado True para dar acceso de juez, False para revocarlo.
     */
    function configurarJuez(address _juez, bool _autorizado) external onlyOwner {
        esJuez[_juez] = _autorizado;
        emit AccesoJuezModificado(_juez, _autorizado);
    }

    function crearEvento(uint256 _costoInscripcion) external onlyOwner {
        totalEventos++; // Incrementamos el contador de IDs

        // Inicializamos el evento en el storage.
        // El array del podio se inicializa con direcciones vacías (address(0)).
        eventos[totalEventos] = Evento({
            costoInscripcion: _costoInscripcion, finalizado: false, podio: [address(0), address(0), address(0)]
        });

        emit EventoCreado(totalEventos, _costoInscripcion);
    }

    // Otras Funciones públicas

    function registrarParticipante(bytes32 _hashIdentidad) external {
        if (participantes[msg.sender].registrado) {
            revert ParticipanteYaRegistrado();
        }

        participantes[msg.sender] = Participante({hashIdentidad: _hashIdentidad, registrado: true});

        emit ParticipanteRegistrado(msg.sender, _hashIdentidad);
    }

    function inscripcionEvento(uint256 _eventoId) external payable {
        if (!participantes[msg.sender].registrado) {
            revert ParticipanteNoRegistrado();
        }
        if (_eventoId == 0 || _eventoId > totalEventos) {
            revert EventoNoExiste();
        }
        if (eventos[_eventoId].finalizado) {
            revert EventoYaFinalizado();
        }
        if (inscritosAEvento[_eventoId][msg.sender]) {
            revert YaInscrito();
        }

        // Validación de Fondos
        if (msg.value != eventos[_eventoId].costoInscripcion) {
            revert InsuficienteETH(msg.value, eventos[_eventoId].costoInscripcion);
        }

        inscritosAEvento[_eventoId][msg.sender] = true;

        emit InscripcionExitosa(_eventoId, msg.sender);
    }

    function finalizarEvento(uint256 _eventoId, address[3] calldata _podio) external onlyJudge {
        if (_eventoId == 0 || _eventoId > totalEventos) revert EventoNoExiste();
        if (eventos[_eventoId].finalizado) revert EventoYaFinalizado();

        // Cambiamos el estado
        eventos[_eventoId].finalizado = true;
        eventos[_eventoId].podio = _podio;

        emit EventoFinalizado(_eventoId, _podio);
    }

    function reclamarReembolso(uint256 _eventoId) external {
        if (_eventoId == 0 || _eventoId > totalEventos) revert EventoNoExiste();
        if (!eventos[_eventoId].finalizado) revert EventoNoFinalizado();
        if (!inscritosAEvento[_eventoId][msg.sender]) revert NoParticipoEnEvento();
        if (reembolsoReclamado[_eventoId][msg.sender]) revert ReembolsoYaReclamado();

        // 2. EFFECTS (Cambios de estado interno)
        // ¡Crucial! Marcamos como cobrado ANTES de enviar el dinero
        reembolsoReclamado[_eventoId][msg.sender] = true;
        uint256 montoAReembolsar = eventos[_eventoId].costoInscripcion;

        // 3. INTERACTIONS (Envío de ETH a un contrato/cuenta externa)
        // Usamos .call que es el método moderno y seguro recomendado en Ethereum
        (bool exito,) = msg.sender.call{value: montoAReembolsar}("");
        if (!exito) revert TransferenciaFallida();

        emit ReembolsoEmitido(_eventoId, msg.sender, montoAReembolsar);
    }

    function obtenerRanking(uint256 _eventoId) external view returns (address[3] memory) {
        // Validación básica
        if (_eventoId == 0 || _eventoId > totalEventos) revert EventoNoExiste();

        // Retornamos el arreglo completo que está en el storage
        // La palabra "memory" es obligatoria al devolver arreglos o textos
        return eventos[_eventoId].podio;
    }

    function obtenerPerfilParticipante(address _participante)
        external
        view
        returns (bytes32 hashIdentidad, bool registrado)
    {
        // Guardamos temporalmente en memoria para optimizar la lectura
        Participante memory p = participantes[_participante];

        return (p.hashIdentidad, p.registrado);
    }
}
