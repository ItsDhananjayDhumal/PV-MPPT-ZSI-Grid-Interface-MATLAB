function [I_ref, D0, state, mppt_data] = current_sweep_mppt(V_pv, I_pv, t, mppt_cfg, reset_flag)
% CURRENT_SWEEP_MPPT Implements periodic and event-driven Current Sweep MPPT.
%
% Inputs:
%   V_pv       : Measured PV array voltage (V)
%   I_pv       : Measured PV array current (A)
%   t          : Current simulation time (s)
%   mppt_cfg   : Configuration parameters struct (from init_params.m)
%   reset_flag : (Optional) Force restart of sweep
%
% Outputs:
%   I_ref      : Target PV current reference for inverter current loop (A)
%   D0         : Calculated shoot-through duty ratio for ZSI boost
%   state      : Current state: 1 = SWEEPING, 2 = HOLD/TRACKING
%   mppt_data  : Struct with tracking metrics (GMPP found, efficiency, etc.)
%
% Architecture:
%   - Dual triggering: Periodic timer (every T_period) + Event-driven (dP > threshold).
%   - Immune to local minima under Partial Shading Conditions (PSC).

    % Persistent variables for state memory
    persistent sm_state sweep_start_time t_last_sweep
    persistent P_max_found I_mpp_found V_mpp_found
    persistent P_hold_prev dP_event_counter
    persistent I_ref_current D0_current

    if nargin < 5
        reset_flag = false;
    end

    % Initialization on first call or explicit reset
    if isempty(sm_state) || reset_flag
        sm_state          = 1;          % Start in SWEEPING state
        sweep_start_time  = t;
        t_last_sweep      = t;
        P_max_found       = 0;
        if isfield(mppt_cfg, 'Imp'), I_mpp_found = mppt_cfg.Imp; else, I_mpp_found = 27.9; end
        if isfield(mppt_cfg, 'Vmp'), V_mpp_found = mppt_cfg.Vmp; else, V_mpp_found = 382.9; end
        if isfield(mppt_cfg, 'Pmp'), P_hold_prev = mppt_cfg.Pmp; else, P_hold_prev = 10680.0; end
        dP_event_counter  = 0;
        if isfield(mppt_cfg, 'I_min'), I_ref_current = mppt_cfg.I_min; else, I_ref_current = 0.5; end
        if isfield(mppt_cfg, 'D0_nom'), D0_current = mppt_cfg.D0_nom; else, D0_current = 0.30; end
    end

    % Compute instantaneous power
    P_inst = V_pv * I_pv;

    % Target DC bus voltage for 440V grid interface
    % Peak phase = 359.3 V -> Peak DC-link needed = 2 * Vph_peak / M_nom = 2 * 359.3 / 0.75 = 958 V
    V_dc_req = 950.0;

    switch sm_state
        case 1
            % =========================================================
            % STATE 1: ACTIVE CURRENT SWEEP
            % =========================================================
            t_sweep_elapsed = t - sweep_start_time;

            if t_sweep_elapsed <= mppt_cfg.sweep_duration
                % Linear ramp of current reference across full array range
                ramp_progress = t_sweep_elapsed / mppt_cfg.sweep_duration;
                I_ref_current = mppt_cfg.I_min + ramp_progress * (mppt_cfg.I_max - mppt_cfg.I_min);

                % During sweep, update maximum power point discovered
                if P_inst > P_max_found && V_pv > 10.0
                    P_max_found = P_inst;
                    I_mpp_found = I_pv;
                    V_mpp_found = V_pv;
                end
                
                % Maintain nominal boost during sweep
                if isfield(mppt_cfg, 'D0_nom'), D0_current = mppt_cfg.D0_nom; else, D0_current = 0.30; end
            else
                % Sweep completed! Transition to HOLD/TRACK
                sm_state = 2;
                
                % Fallback protection in case of low reading
                if P_max_found < 50.0
                    if isfield(mppt_cfg, 'I_min'), I_mpp_found = mppt_cfg.I_min; else, I_mpp_found = 0.5; end
                    if isfield(mppt_cfg, 'Vmp'), V_mpp_found = mppt_cfg.Vmp; else, V_mpp_found = 382.9; end
                    P_max_found = 100.0;
                end

                I_ref_current    = I_mpp_found;
                P_hold_prev      = P_max_found;
                t_last_sweep     = t;
                dP_event_counter = 0;

                % Compute optimized shoot-through duty ratio D0 for ZSI
                % B = V_dc_req / V_mpp
                % D0 = (B - 1) / (2 * B)
                B_opt = max(1.1, min(4.0, V_dc_req / max(50.0, V_mpp_found)));
                D0_calc = (B_opt - 1) / (2 * B_opt);
                D0_current = max(0.08, min(0.33, D0_calc)); % Enforce SBC safe bounds
            end

        case 2
            % =========================================================
            % STATE 2: HOLD & TRACK AT DETECTED GMPP
            % =========================================================
            I_ref_current = I_mpp_found;

            % 1. Periodic Trigger Evaluation
            t_since_sweep = t - t_last_sweep;
            if t_since_sweep >= mppt_cfg.T_period
                % Periodic timer expired -> Initiate re-sweep
                sm_state         = 1;
                sweep_start_time = t;
                P_max_found      = 0;
            elseif t_since_sweep >= 0.025 % Blanking window: allow current loop to settle at MPP
                % 2. Event-Driven Trigger Evaluation
                if P_hold_prev > 100.0
                    rel_dP = abs(P_inst - P_hold_prev) / P_hold_prev;
                else
                    rel_dP = abs(P_inst - P_hold_prev) / 500.0;
                end

                if rel_dP > mppt_cfg.dP_threshold
                    dP_event_counter = dP_event_counter + 1;
                    % Debounce filter: require sustained delta for at least 80 cycles (4 ms)
                    if dP_event_counter >= 80
                        % Environmental shift confirmed -> Trigger instant sweep!
                        sm_state         = 1;
                        sweep_start_time = t;
                        P_max_found      = 0;
                        dP_event_counter = 0;
                    end
                else
                    dP_event_counter = max(0, dP_event_counter - 1);
                    % Adaptive fine update of hold power
                    P_hold_prev = 0.98 * P_hold_prev + 0.02 * P_inst;
                end
            else
                % Inside settling window: align hold power with settled measurement
                dP_event_counter = 0;
                if t_since_sweep >= 0.010 && P_inst > 100.0
                    P_hold_prev = P_inst;
                end
            end
    end

    % Assign outputs
    I_ref = I_ref_current;
    D0    = D0_current;
    state = sm_state;

    if nargout >= 4
        mppt_data.P_mpp_found = P_max_found;
        mppt_data.I_mpp_found = I_mpp_found;
        mppt_data.V_mpp_found = V_mpp_found;
        mppt_data.P_inst      = P_inst;
        mppt_data.state_name  = sm_state;
    end
end
