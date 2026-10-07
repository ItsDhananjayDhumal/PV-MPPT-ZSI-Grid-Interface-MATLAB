function [V_pv, P_pv, info] = pv_array_model(I_pv, G, T_c, pv_arr, pv_mod, pv_const, shading_profile)
% PV_ARRAY_MODEL Evaluates the PV array voltage and power for a given current.
%
% Inputs:
%   I_pv            : Array terminal current (A)
%   G               : Irradiance (W/m^2) [Scalar for uniform, or vector for shaded groups]
%   T_c             : Cell temperature (deg C)
%   pv_arr          : Struct with array architecture parameters
%   pv_mod          : Struct with module parameters
%   pv_const        : Struct with physical constants
%   shading_profile : (Optional) Struct defining partial shading groups
%
% Outputs:
%   V_pv            : PV Array terminal voltage (V)
%   P_pv            : PV Array instantaneous power (W)
%   info            : Struct with detailed curve data and true MPP
%
% Reference:
%   Single-diode 5-parameter model with bypass diode conduction under PSC.

    if nargin < 7 || isempty(shading_profile)
        is_shaded = false;
    else
        is_shaded = true;
    end

    % Thermal voltage calculation
    T_k     = T_c + 273.15;
    T_ref_k = pv_mod.T_ref;
    k_B     = pv_const.k_boltz;
    q_e     = pv_const.q_elem;
    n_d     = pv_const.diode_n;

    if ~is_shaded
        % -------------------------------------------------------------
        % UNIFORM IRRADIANCE CASE
        % -------------------------------------------------------------
        % Photo-generated current (scaled for N_par strings)
        delta_T = T_c - 25.0;
        Iph_mod = (pv_mod.Isc_mod + pv_mod.Ki * delta_T) * (G / pv_mod.G_ref);
        Iph_arr = pv_arr.N_par * Iph_mod;

        % Diode reverse saturation current
        Eg = 1.12; % Silicon bandgap energy (eV)
        T_ref_k = pv_mod.T_ref;
        I0_mod = (pv_mod.Isc_mod / (exp((pv_mod.Voc_mod + pv_mod.Kv * delta_T) / ...
                 (n_d * pv_mod.N_cells * k_B * T_k / q_e)) - 1));
        I0_arr = pv_arr.N_par * I0_mod;

        Vt_total = (pv_arr.N_ser * pv_mod.N_cells * k_B * T_k) / q_e;
        Rs_total  = pv_arr.Rs * (pv_arr.N_ser / pv_arr.N_par);
        Rsh_total = pv_arr.Rsh * (pv_arr.N_ser / pv_arr.N_par);

        % Robust analytical single-diode formulation:
        % V(I) = n*Vt * ln( (Iph - I)/I0 + 1 ) - I*Rs
        i_clamped = max(0, min(I_pv, Iph_arr * 0.999));
        arg_log   = max(1e-12, (Iph_arr - i_clamped) ./ I0_arr + 1.0);
        V_pv      = max(0, n_d * Vt_total .* log(arg_log) - i_clamped .* Rs_total);
        P_pv      = V_pv .* I_pv;

    else
        % -------------------------------------------------------------
        % PARTIAL SHADING CASE (Multi-Group Bypass Diodes)
        % -------------------------------------------------------------
        groups = shading_profile.groups;
        num_g = length(groups);
        V_pv = zeros(size(I_pv));

        for g_idx = 1:num_g
            grp = groups(g_idx);
            G_g = grp.G;
            N_s_g = grp.N_ser_sub;
            N_p_g = pv_arr.N_par;

            delta_T = T_c - 25.0;
            Iph_g = N_p_g * (pv_mod.Isc_mod + pv_mod.Ki * delta_T) * (G_g / pv_mod.G_ref);
            Vt_g  = (N_s_g * pv_mod.N_cells * k_B * T_k) / q_e;
            I0_g  = N_p_g * (pv_mod.Isc_mod / (exp(pv_mod.Voc_mod / (n_d * pv_mod.N_cells * k_B * T_ref_k / q_e)) - 1));
            Rs_g  = pv_arr.Rs * (N_s_g / N_p_g);

            v_grp = zeros(size(I_pv));
            for idx = 1:length(I_pv)
                i_val = I_pv(idx);
                if i_val < Iph_g * 0.999
                    arg_log = max(1e-12, (Iph_g - i_val) / I0_g + 1.0);
                    v_grp(idx) = max(0, n_d * Vt_g * log(arg_log) - i_val * Rs_g);
                else
                    % Current exceeds group generation -> Bypass diode conducts!
                    v_grp(idx) = -0.7;
                end
            end
            V_pv = V_pv + v_grp;
        end
        V_pv = max(0, V_pv);
        P_pv = V_pv .* I_pv;
    end

    % -------------------------------------------------------------
    % Optional Full Characteristic Curve & True GMPP Computation
    % -------------------------------------------------------------
    if nargout >= 3
        % Sweep fine current vector from 0 to Isc
        I_sweep_eval = linspace(0, pv_arr.Isc * 0.998, 500);
        if ~is_shaded
            [V_sweep_eval, P_sweep_eval] = pv_array_model(I_sweep_eval, G, T_c, pv_arr, pv_mod, pv_const);
        else
            [V_sweep_eval, P_sweep_eval] = pv_array_model(I_sweep_eval, G, T_c, pv_arr, pv_mod, pv_const, shading_profile);
        end
        [P_max_true, max_idx] = max(P_sweep_eval);
        info.I_sweep = I_sweep_eval;
        info.V_sweep = V_sweep_eval;
        info.P_sweep = P_sweep_eval;
        info.P_max_true = P_max_true;
        info.V_mpp_true = V_sweep_eval(max_idx);
        info.I_mpp_true = I_sweep_eval(max_idx);
    end
end
