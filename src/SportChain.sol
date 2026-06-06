// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract SportChain {

    struct Participante {
        bytes32 hashIdentidad; // Huella digital de sus datos (fuera de la cadena)
        bool registrado;       // Flag para validar si existe en la plataforma
    }

    struct Evento {
        uint256 costoInscripcion; // Costo en wei para asegurar cupo
        bool finalizado;          // Estado de la competencia
        address[3] podio;         // Espacio acotado para los 3 ganadores (Push)
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

    // Contador global para generar los IDs de eventos secuenciales
    uint256 public totalEventos;

    // ==========================================
    // ERRORES PERSONALIZADOS (CUSTOM ERRORS - Ahorro de Gas)
    // ==========================================
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

    // ==========================================
    // EVENTOS (Para comunicación con el Frontend/DApp)
    // ==========================================
    event OwnerCambiado(address indexed antiguoOwner, address indexed nuevoOwner);
    event AccesoJuezModificado(address indexed juez, bool autorizado);
    event ParticipanteRegistrado(address indexed participante, bytes32 hashIdentidad);
    event EventoCreado(uint256 indexed eventoId, uint256 costoInscripcion);
    event InscripcionExitosa(uint256 indexed eventoId, address indexed participante);
    event CompetenciaFinalizada(uint256 indexed eventoId, address[3] podio);
    event MedallaGeneralReclamada(uint256 indexed eventoId, address indexed participante);

    // ==========================================
    // MODIFICADORES (CONTROL DE ACCESO)
    // ==========================================
    
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

    // ==========================================
    // CONSTRUCTOR (Inicialización de Gobernanza)
    // ==========================================
    /**
     * @param _juez1 Dirección del primer compañero del grupo
     * @param _juez2 Dirección del segundo compañero del grupo
     */
    constructor(address _juez1, address _juez2) {
        // Quien hace el deploy (tú) queda registrado como el único Admin Supremo
        owner = msg.sender;
        emit OwnerCambiado(address(0), msg.sender);
        
        // Autorizamos inmediatamente a tus otros dos compañeros como los jueces iniciales
        esJuez[_juez1] = true;
        esJuez[_juez2] = true;
        emit AccesoJuezModificado(_juez1, true);
        emit AccesoJuezModificado(_juez2, true);
    }

    // ==========================================
    // FUNCIONES ADMINISTRATIVAS (ONLY OWNER)
    // ==========================================

    /**
     * @notice Permite al Admin agregar nuevos jueces o revocar accesos en el futuro.
     * @param _juez Dirección de la billetera a modificar.
     * @param _autorizado True para dar acceso de juez, False para revocarlo.
     */
    function configurarJuez(address _juez, bool _autorizado) external onlyOwner {
        esJuez[_juez] = _autorizado;
        emit AccesoJuezModificado(_juez, _autorizado);
    }
}