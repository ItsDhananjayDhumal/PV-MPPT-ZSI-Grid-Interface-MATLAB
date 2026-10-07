% =========================================================================
% init_params.m
% =========================================================================
% Project: MPPT Simulation of PV Panel using Current Sweep Approach with
%          Z-Source Inverter (ZSI) Interfaced to 440V, 50Hz Grid.
%
% Rating:  10 kW PV Array
% Grid:    440 V (Line-to-Line RMS), 50 Hz Three-Phase Utility Grid
% =========================================================================

% (Note: clear and clc omitted so this script safely executes inside functions and callbacks)
fprintf('===================================================================\n');
fprintf('Initializing Parameters: 10kW PV Array + ZSI + 440V 50Hz Grid\n');
fprintf('===================================================================\n');

%% 1. Simulation Timing & Solvers
Ts          = 5e-6;          % Fundamental simulation time step (s) [5 microseconds]
T_stop      = 3.5;           % Default simulation duration (s)
f_sw        = 10e3;          % Inverter switching frequency (10 kHz)
T_sw_period = 1 / f_sw;      % Switching period (100 microseconds)

%% 2. PV Module & Array Specifications (10 kW Target)
% Based on standard high-efficiency crystalline silicon modules:
% Single Module Ratings at STC (1000 W/m^2, 25 deg C):
pv_mod.Pmp_mod  = 305.0;     % Peak power per module (W)
pv_mod.Vmp_mod  = 54.7;      % Voltage at MPP (V)
pv_mod.Imp_mod  = 5.58;      % Current at MPP (A)
pv_mod.Voc_mod  = 64.2;      % Open-circuit voltage (V)
pv_mod.Isc_mod  = 5.96;      % Short-circuit current (A)
pv_mod.Kv       = -0.177;    % Temperature coefficient of Voc (V/deg C)
pv_mod.Ki       = 0.0035;    % Temperature coefficient of Isc (A/deg C)
pv_mod.N_cells  = 96;        % Cells per module
pv_mod.T_ref    = 25 + 273.15; % Reference temperature (K)
pv_mod.G_ref    = 1000;      % Reference irradiance (W/m^2)

% Physical constants
pv_const.k_boltz = 1.380649e-23; % Boltzmann constant (J/K)
pv_const.q_elem  = 1.602176e-19; % Electron charge (C)
pv_const.diode_n = 1.25;         % Diode ideality factor

% Array Architecture for 10 kW:
% N_ser: 7 modules in series per string  -> Vmp_arr = 7 * 54.7 = 382.9 V, Voc_arr = 449.4 V
% N_par: 5 parallel strings             -> Imp_arr = 5 * 5.58 = 27.9 A,  Isc_arr = 29.8 A
% Total P_mp = 382.9 V * 27.9 A = 10,683 W (~10.7 kW at STC)
pv_arr.N_ser    = 7;         % Series modules per string
pv_arr.N_par    = 5;         % Number of parallel strings
pv_arr.Vmp      = pv_arr.N_ser * pv_mod.Vmp_mod; % 382.9 V
pv_arr.Imp      = pv_arr.N_par * pv_mod.Imp_mod; % 27.9 A
pv_arr.Pmp      = pv_arr.Vmp * pv_arr.Imp;       % 10.68 kW
pv_arr.Voc      = pv_arr.N_ser * pv_mod.Voc_mod; % 449.4 V
pv_arr.Isc      = pv_arr.N_par * pv_mod.Isc_mod; % 29.8 A

% Calculate internal diode saturation & series/shunt parameters
T_k = pv_mod.T_ref;
Vt  = (pv_arr.N_ser * pv_mod.N_cells * pv_const.k_boltz * T_k) / pv_const.q_elem;
pv_arr.Vt = Vt;
pv_arr.I0 = (pv_arr.Isc) / (exp(pv_arr.Voc / (pv_const.diode_n * Vt)) - 1);
pv_arr.Rs = 0.25;            % Equivalent series resistance (Ohms)
pv_arr.Rsh = 1500;           % Equivalent shunt resistance (Ohms)

%% 3. Z-Source Inverter (ZSI) Impedance Network Design
% Symmetrical X-shaped network: L1 = L2 = Lz, C1 = C2 = Cz
% Requirements:
% Grid line-to-line RMS = 440 V -> Peak line-to-line = 440 * sqrt(2) = 622.3 V.
% Peak phase voltage = 622.3 / sqrt(3) = 359.2 V.
% To feed a 440 V grid with modulation index M = 0.75 - 0.8:
% Inverter peak DC link voltage required:
% V_dc_peak = (2 / M) * V_ph_peak = (2 / 0.75) * 359.2 = 957.9 V.
% With PV at Vmp = 382.9 V, required Boost Factor:
% B = V_dc_peak / V_pv = 958 / 383 = 2.50.
% Boost factor relationship: B = 1 / (1 - 2*D0)
% 1 - 2*D0 = 1 / 2.50 = 0.40  ->  D0 = 0.30 (Shoot-Through duty ratio).
% Simple Boost Control (SBC) condition: D0 <= 1 - M  (0.30 <= 1 - 0.70 = 0.30).

zsi.L1   = 3.5e-3;           % Z-network inductor L1 (H) [3.5 mH]
zsi.L2   = 3.5e-3;           % Z-network inductor L2 (H) [3.5 mH]
zsi.C1   = 850e-6;           % Z-network capacitor C1 (F) [850 uF]
zsi.C2   = 850e-6;           % Z-network capacitor C2 (F) [850 uF]
zsi.r_L  = 0.04;             % Inductor parasitic resistance (Ohms)
zsi.r_C  = 0.01;             % Capacitor ESR (Ohms)
zsi.D0_nom = 0.30;           % Nominal shoot-through duty ratio
zsi.M_nom  = 0.70;           % Nominal modulation index
zsi.B_nom  = 1 / (1 - 2*zsi.D0_nom); % Boost factor = 2.50

%% 4. Three-Phase Grid & Output Interface Filter
grid_sys.V_LL_rms = 440;     % Line-to-line RMS grid voltage (V)
grid_sys.f_grid   = 50.0;    % Grid fundamental frequency (Hz)
grid_sys.omega    = 2*pi*grid_sys.f_grid; % Angular frequency (rad/s)
grid_sys.V_ph_rms = grid_sys.V_LL_rms / sqrt(3); % Phase RMS voltage (254.03 V)
grid_sys.V_ph_peak= grid_sys.V_ph_rms * sqrt(2); % Phase peak voltage (359.26 V)

% Grid interface inductor filter (Lf, Rf)
grid_sys.Lf       = 4.5e-3;  % Inverter interface inductance (H) [4.5 mH]
grid_sys.Rf       = 0.15;    % Filter inductor resistance (Ohms)
grid_sys.Cf       = 25e-6;   % Filter capacitor for harmonic suppression (F) [25 uF]

%% 5. Grid Synchronous Inverter Vector Control (dq Frame)
% Inner current loop bandwidth ~ 1 kHz (omega_bw = 2*pi*1000 rad/s)
omega_bw_i        = 2*pi*800;
ctrl.Kp_id        = grid_sys.Lf * omega_bw_i;               % Proportional gain
ctrl.Ki_id        = (grid_sys.Rf + 0.1) * omega_bw_i * 10;  % Integral gain
ctrl.Kp_iq        = ctrl.Kp_id;
ctrl.Ki_iq        = ctrl.Ki_id;

% PLL Parameters (Phase-Locked Loop)
ctrl.pll_Kp       = 60.0;    % PLL proportional gain
ctrl.pll_Ki       = 1400.0;  % PLL integral gain

% Outer DC-Link / Power Controller
ctrl.Kp_p         = 0.05;    % Power control proportional gain
ctrl.Ki_p         = 2.5;     % Power control integral gain

%% 6. Current Sweep MPPT Algorithm Specifications
% Fast sweep approach:
mppt.I_min          = 0.5;   % Minimum current in sweep (A)
mppt.I_max          = 32.0;  % Maximum current in sweep (A) [above Isc_arr]
mppt.sweep_duration = 0.040; % Duration of one sweep (s) [40 ms fast scan]
mppt.sweep_rate     = (mppt.I_max - mppt.I_min) / mppt.sweep_duration; % A/s
mppt.T_period       = 0.800; % Periodic sweep interval (s) [every 800 ms]
mppt.dP_threshold   = 0.05;  % Event-driven sweep threshold: 5% relative power change
mppt.sample_time    = 1e-4;  % MPPT sampling time (100 us)
mppt.settle_time    = 0.005; % Settling time after sweep (5 ms)
mppt.Imp            = pv_arr.Imp; % Nominal array Imp (27.9 A)
mppt.Vmp            = pv_arr.Vmp; % Nominal array Vmp (382.9 V)
mppt.Pmp            = pv_arr.Pmp; % Nominal array Pmp (10.68 kW)
mppt.D0_nom         = zsi.D0_nom; % Nominal boost duty ratio (0.30)

%% 7. Summary Display
fprintf('PV Array:       %d Series x %d Parallel = %d Modules\n', pv_arr.N_ser, pv_arr.N_par, pv_arr.N_ser*pv_arr.N_par);
fprintf('Nominal Rating: Pmp = %.2f kW, Vmp = %.1f V, Imp = %.1f A\n', pv_arr.Pmp/1e3, pv_arr.Vmp, pv_arr.Imp);
fprintf('ZSI Parameters: L = %.1f mH, C = %.0f uF, Nom. Boost B = %.2f\n', zsi.L1*1e3, zsi.C1*1e6, zsi.B_nom);
fprintf('Grid:           %.0f V L-L RMS, %.0f Hz, Phase Peak = %.1f V\n', grid_sys.V_LL_rms, grid_sys.f_grid, grid_sys.V_ph_peak);
fprintf('Current Sweep:  Periodic (every %.1f s) + Event-Driven (dP > %.0f%%)\n', mppt.T_period, mppt.dP_threshold*100);
fprintf('===================================================================\n');
fprintf('Parameter initialization complete.\n');
