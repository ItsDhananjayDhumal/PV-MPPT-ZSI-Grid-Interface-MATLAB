function sim_results = pv_zsi_grid_sim(test_case_id, custom_params)
% PV_ZSI_GRID_SIM High-fidelity time-domain simulation engine for:
% 10 kW PV Array + Current Sweep MPPT + Z-Source Inverter + 440V 50Hz Grid.
%
% Inputs:
%   test_case_id  : 1 = Case 1: STC (1000 W/m^2, 25 deg C)
%                   2 = Case 2: Rapid Irradiance Step (1000 -> 500 -> 800 W/m^2)
%                   3 = Case 3: Partial Shading Condition (PSC Multi-Peak)
%   custom_params : (Optional) Overriding parameter structure
%
% Output:
%   sim_results   : Structure containing time vectors and all logged system states:
%                   - PV: Vpv, Ipv, Ppv, P_mpp_true, tracking_efficiency
%                   - ZSI: Vc1, Vc2, iL1, iL2, V_dc_peak, B_boost, D0
%                   - Grid: va, vb, vc, ia, ib, ic, P_grid, Q_grid, PF
%                   - MPPT: state (sweeping vs holding), sweep_triggers

    % Load base parameters
    init_params;

    if nargin >= 2 && ~isempty(custom_params)
        % Apply any user parameter overrides
        fn = fieldnames(custom_params);
        for k = 1:length(fn)
            eval([fn{k} ' = custom_params.' fn{k} ';']);
        end
    end

    % Define test case specific profiles
    switch test_case_id
        case 1
            % =========================================================
            % CASE 1: Standard Test Condition (STC)
            % =========================================================
            case_name = 'Case 1: Standard Test Condition (STC: 1000 W/m^2, 25 deg C)';
            t_end = 2.0; % Simulation time (s)
            G_profile_fn = @(t) 1000.0;
            T_profile_fn = @(t) 25.0;
            is_shading = false;
            shading_profile = [];

        case 2
            % =========================================================
            % CASE 2: Rapid Irradiance Step Change
            % =========================================================
            case_name = 'Case 2: Rapid Irradiance Step (1000 -> 500 -> 800 W/m^2)';
            t_end = 3.2; % Simulation time (s)
            G_profile_fn = @(t) 1000.0*(t < 1.0) + 500.0*(t >= 1.0 & t < 2.1) + 800.0*(t >= 2.1);
            T_profile_fn = @(t) 25.0;
            is_shading = false;
            shading_profile = [];

        case 3
            % =========================================================
            % CASE 3: Partial Shading Condition (PSC Multi-Peak GMPP)
            % =========================================================
            case_name = 'Case 3: Partial Shading Condition (PSC - Multi-Peak Curve)';
            t_end = 2.5; % Simulation time (s)
            G_profile_fn = @(t) 1000.0; % Base
            T_profile_fn = @(t) 25.0;
            is_shading = true;
            % 3 non-uniformly shaded groups across the 7 series modules:
            % Group 1: 3 modules @ 1000 W/m^2
            % Group 2: 2 modules @ 600 W/m^2
            % Group 3: 2 modules @ 300 W/m^2
            shading_profile.groups = [
                struct('N_ser_sub', 3, 'G', 1000.0)
                struct('N_ser_sub', 2, 'G', 600.0)
                struct('N_ser_sub', 2, 'G', 300.0)
            ];
            % At t >= 1.3s, change shading pattern dynamically:
            shading_profile_t2.groups = [
                struct('N_ser_sub', 3, 'G', 800.0)
                struct('N_ser_sub', 2, 'G', 400.0)
                struct('N_ser_sub', 2, 'G', 200.0)
            ];
    end

    fprintf('\n>>> Running Simulation: %s <<<\n', case_name);

    % Precompute true MPP power to avoid recomputing sweeps inside the time-loop
    fprintf('  Precomputing reference MPP baselines...\n');
    if test_case_id == 1
        [~, ~, info1] = pv_array_model(0, 1000.0, 25.0, pv_arr, pv_mod, pv_const);
        P_mpp_ref_1000 = info1.P_max_true;
    elseif test_case_id == 2
        [~, ~, info1000] = pv_array_model(0, 1000.0, 25.0, pv_arr, pv_mod, pv_const);
        [~, ~, info500]  = pv_array_model(0, 500.0, 25.0, pv_arr, pv_mod, pv_const);
        [~, ~, info800]  = pv_array_model(0, 800.0, 25.0, pv_arr, pv_mod, pv_const);
        P_mpp_ref_1000 = info1000.P_max_true;
        P_mpp_ref_500  = info500.P_max_true;
        P_mpp_ref_800  = info800.P_max_true;
    else
        [~, ~, info_s1] = pv_array_model(0, 1000.0, 25.0, pv_arr, pv_mod, pv_const, shading_profile);
        [~, ~, info_s2] = pv_array_model(0, 1000.0, 25.0, pv_arr, pv_mod, pv_const, shading_profile_t2);
        P_mpp_ref_s1 = info_s1.P_max_true;
        P_mpp_ref_s2 = info_s2.P_max_true;
    end

    % Simulation discretization setup
    dt = 50e-6; % 50 microseconds resolution for fast, high-accuracy dynamic simulation
    time = (0:dt:t_end)';
    N_steps = length(time);

    % Pre-allocate logging arrays
    log_t           = time;
    log_G           = zeros(N_steps, 1);
    log_Vpv         = zeros(N_steps, 1);
    log_Ipv         = zeros(N_steps, 1);
    log_Ppv         = zeros(N_steps, 1);
    log_Pmax_true   = zeros(N_steps, 1);
    log_Vc          = zeros(N_steps, 1);
    log_iL          = zeros(N_steps, 1);
    log_Vdc_peak    = zeros(N_steps, 1);
    log_B           = zeros(N_steps, 1);
    log_D0          = zeros(N_steps, 1);
    log_M           = zeros(N_steps, 1);
    log_mppt_state  = zeros(N_steps, 1);
    log_id          = zeros(N_steps, 1);
    log_iq          = zeros(N_steps, 1);
    log_id_ref      = zeros(N_steps, 1);
    log_Pgrid       = zeros(N_steps, 1);
    log_Qgrid       = zeros(N_steps, 1);
    log_PF          = zeros(N_steps, 1);
    log_vga         = zeros(N_steps, 1);
    log_iga         = zeros(N_steps, 1);

    % Initial Dynamic State Conditions
    v_c = 650.0;     % Initial ZSI capacitor voltage (V) near nominal operating point
    i_l = 15.0;      % Initial ZSI inductor current (A)
    i_d = 5.0;       % Initial d-axis grid current (A)
    i_q = 0.0;       % Initial q-axis grid current (A)
    v_pv = 380.0;    % Initial PV voltage (V)
    i_pv = 1.0;      % Initial PV current (A)
    int_id_err = 0.0;% Inner loop integrator
    int_iq_err = 0.0;

    % Reset MPPT persistent controller
    clear current_sweep_mppt;

    % Progress reporting interval
    report_step = floor(N_steps / 5);

    % Main Simulation Time Loop
    for k = 1:N_steps
        t_curr = time(k);

        % 1. Determine environmental conditions
        G_curr = G_profile_fn(t_curr);
        T_curr = T_profile_fn(t_curr);

        if is_shading
            if test_case_id == 3 && t_curr >= 1.3
                curr_shade = shading_profile_t2;
                P_mpp_true = P_mpp_ref_s2;
            else
                curr_shade = shading_profile;
                P_mpp_true = P_mpp_ref_s1;
            end
        else
            curr_shade = [];
            if test_case_id == 1
                P_mpp_true = P_mpp_ref_1000;
            else
                if t_curr < 1.0
                    P_mpp_true = P_mpp_ref_1000;
                elseif t_curr < 2.1
                    P_mpp_true = P_mpp_ref_500;
                else
                    P_mpp_true = P_mpp_ref_800;
                end
            end
        end

        % 2. Current Sweep MPPT Algorithm
        [I_ref, D0, mppt_st, ~] = current_sweep_mppt(v_pv, i_pv, t_curr, mppt);

        % 3. PV Array Electrical Interaction
        % Fast current regulation: PV terminal current tracks I_ref with PV capacitance dynamic
        tau_pv = 0.5e-3; % 0.5 ms current tracking loop response for sharp sweep fidelity
        di_pv = (I_ref - i_pv) / tau_pv;
        i_pv = max(0, min(pv_arr.Isc * 1.02, i_pv + di_pv * dt));

        % PV terminal voltage evaluation (single evaluation per time step)
        if is_shading
            v_pv = pv_array_model(i_pv, G_curr, T_curr, pv_arr, pv_mod, pv_const, curr_shade);
        else
            v_pv = pv_array_model(i_pv, G_curr, T_curr, pv_arr, pv_mod, pv_const);
        end
        P_pv = v_pv * i_pv;

        % 4. Z-Source Inverter Dynamics
        % Shoot-through duty ratio limits
        D0_eff = max(0.05, min(0.33, D0));
        B_factor = 1 / (1 - 2*D0_eff);
        Vdc_peak = max(v_pv, 2 * v_c - v_pv);

        % Inverter AC Active Power Reference and Grid Current Ref
        P_target = max(50.0, P_pv * 0.965); % 96.5% conversion efficiency
        id_ref = (2/3) * (P_target / grid_sys.V_ph_peak);
        iq_ref = 0.0; % Unity power factor command

        % Inverter DC side current drawn from Z-network
        I_dc_inv = max(0.1, P_target / max(100.0, Vdc_peak));

        % Z-Source Network Differential Equations (Averaged state-space)
        % Lz * di_l/dt = (1 - D0)*v_pv - (1 - 2*D0)*v_c - r_L*i_l
        % Cz * dv_c/dt = (1 - 2*D0)*i_l - (1 - D0)*I_dc_inv
        di_l = ((1 - D0_eff)*v_pv - (1 - 2*D0_eff)*v_c - zsi.r_L*i_l) / zsi.L1;
        dv_c = ((1 - 2*D0_eff)*i_l - (1 - D0_eff)*I_dc_inv) / zsi.C1;

        i_l = max(0, min(80.0, i_l + di_l * dt));
        v_c = max(v_pv*0.5, min(1200.0, v_c + dv_c * dt));

        % 5. Inverter DQ Current Control & Grid Interface
        % Inner current loops with anti-windup clamping
        err_id = id_ref - i_d;
        err_iq = iq_ref - i_q;
        int_id_err = max(-50.0, min(50.0, int_id_err + err_id * dt));
        int_iq_err = max(-50.0, min(50.0, int_iq_err + err_iq * dt));

        % Modulation reference signals in dq frame
        vd_ref = grid_sys.V_ph_peak + grid_sys.Rf * i_d - grid_sys.omega * grid_sys.Lf * i_q ...
                 + ctrl.Kp_id * err_id + ctrl.Ki_id * int_id_err;
        vq_ref = grid_sys.Rf * i_q + grid_sys.omega * grid_sys.Lf * i_d ...
                 + ctrl.Kp_iq * err_iq + ctrl.Ki_iq * int_iq_err;

        % Modulation index
        V_inv_mag = sqrt(vd_ref^2 + vq_ref^2);
        M_mod = min(1.0 - D0_eff, (2 * V_inv_mag) / max(100.0, Vdc_peak));

        % Grid current dynamics (RL filter)
        % Lf * di_d/dt = vd_ref - V_ph_peak - Rf * i_d + omega * Lf * i_q
        % Lf * di_q/dt = vq_ref - Rf * i_q - omega * Lf * i_d
        did_dt = (vd_ref - grid_sys.V_ph_peak - grid_sys.Rf * i_d + grid_sys.omega * grid_sys.Lf * i_q) / grid_sys.Lf;
        diq_dt = (vq_ref - grid_sys.Rf * i_q - grid_sys.omega * grid_sys.Lf * i_d) / grid_sys.Lf;

        i_d = i_d + did_dt * dt;
        i_q = i_q + diq_dt * dt;

        % Grid Active & Reactive Powers
        P_grid = (3/2) * grid_sys.V_ph_peak * i_d;
        Q_grid = -(3/2) * grid_sys.V_ph_peak * i_q;
        S_grid = sqrt(P_grid^2 + Q_grid^2);
        if S_grid > 10.0
            PF_val = P_grid / S_grid;
        else
            PF_val = 1.0;
        end

        % Three-phase instantaneous representations
        theta_g = grid_sys.omega * t_curr;
        v_ga = grid_sys.V_ph_peak * sin(theta_g);
        i_ga = i_d * sin(theta_g) + i_q * cos(theta_g);

        % 6. Data Logging
        log_G(k)          = G_curr;
        log_Vpv(k)        = v_pv;
        log_Ipv(k)        = i_pv;
        log_Ppv(k)        = P_pv;
        log_Pmax_true(k)  = P_mpp_true;
        log_Vc(k)         = v_c;
        log_iL(k)         = i_l;
        log_Vdc_peak(k)   = Vdc_peak;
        log_B(k)          = B_factor;
        log_D0(k)         = D0_eff;
        log_M(k)          = M_mod;
        log_mppt_state(k) = mppt_st;
        log_id(k)         = i_d;
        log_iq(k)         = i_q;
        log_id_ref(k)     = id_ref;
        log_Pgrid(k)      = P_grid;
        log_Qgrid(k)      = Q_grid;
        log_PF(k)         = PF_val;
        log_vga(k)        = v_ga;
        log_iga(k)        = i_ga;

        if mod(k, report_step) == 0
            fprintf('  Simulation Progress: %3.0f%% (t = %.2f s / %.2f s) | P_pv = %.2f kW | P_grid = %.2f kW\n', ...
                    (k/N_steps)*100, t_curr, t_end, P_pv/1e3, P_grid/1e3);
        end
    end

    % Package outputs
    sim_results.case_id         = test_case_id;
    sim_results.case_name       = case_name;
    sim_results.time            = log_t;
    sim_results.G               = log_G;
    sim_results.Vpv             = log_Vpv;
    sim_results.Ipv             = log_Ipv;
    sim_results.Ppv             = log_Ppv;
    sim_results.Pmax_true       = log_Pmax_true;
    sim_results.tracking_eff    = mean(log_Ppv(log_mppt_state==2) ./ log_Pmax_true(log_mppt_state==2)) * 100;
    sim_results.Vc              = log_Vc;
    sim_results.iL              = log_iL;
    sim_results.Vdc_peak        = log_Vdc_peak;
    sim_results.B               = log_B;
    sim_results.D0              = log_D0;
    sim_results.M               = log_M;
    sim_results.mppt_state      = log_mppt_state;
    sim_results.id              = log_id;
    sim_results.iq              = log_iq;
    sim_results.id_ref          = log_id_ref;
    sim_results.Pgrid           = log_Pgrid;
    sim_results.Qgrid           = log_Qgrid;
    sim_results.PF              = log_PF;
    sim_results.vga             = log_vga;
    sim_results.iga             = log_iga;

    fprintf('>>> Simulation Completed Successfully! <<<\n');
    fprintf('    Average MPPT Tracking Efficiency in Hold/Track: %.2f%%\n\n', sim_results.tracking_eff);
end
