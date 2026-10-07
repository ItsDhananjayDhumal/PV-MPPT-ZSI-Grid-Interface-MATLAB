function res = run_case1_stc()
% =========================================================================
% run_case1_stc.m
% =========================================================================
% Case 1: Standard Test Condition (STC: 1000 W/m^2, 25 deg C)
%
% Validates:
% 1. Initial Current Sweep execution and fast convergence to MPP (~10.7 kW).
% 2. ZSI capacitor voltage boost and peak DC bus stabilization (>900 V).
% 3. Three-phase 440V grid injection at unity power factor (PF > 0.999).
% =========================================================================

fprintf('===================================================================\n');
fprintf('RUNNING CASE 1: Standard Test Condition (STC)\n');
fprintf('===================================================================\n');

% Run the simulation
res = pv_zsi_grid_sim(1);

% Extract steady-state metrics (evaluating in hold state after t = 0.5 s)
ss_idx = res.time >= 0.5 & res.mppt_state == 2;
mean_Ppv     = mean(res.Ppv(ss_idx));
mean_Pmax    = mean(res.Pmax_true(ss_idx));
mean_Vpv     = mean(res.Vpv(ss_idx));
mean_Ipv     = mean(res.Ipv(ss_idx));
mean_Vc      = mean(res.Vc(ss_idx));
mean_Vdc_pk  = mean(res.Vdc_peak(ss_idx));
mean_B       = mean(res.B(ss_idx));
mean_Pgrid   = mean(res.Pgrid(ss_idx));
mean_Qgrid   = mean(res.Qgrid(ss_idx));
mean_PF      = mean(res.PF(ss_idx));
eff_mppt     = (mean_Ppv / mean_Pmax) * 100;
eff_inverter = (mean_Pgrid / mean_Ppv) * 100;

fprintf('--- Case 1 Key Performance Metrics ---\n');
fprintf('PV Generated Power:        %.2f kW (Target True MPP: %.2f kW)\n', mean_Ppv/1e3, mean_Pmax/1e3);
fprintf('MPPT Tracking Efficiency:  %.2f %%\n', eff_mppt);
fprintf('PV Operating Point:        Vmp = %.1f V, Imp = %.2f A\n', mean_Vpv, mean_Ipv);
fprintf('ZSI Capacitor Voltage:     Vc = %.1f V\n', mean_Vc);
fprintf('ZSI Peak DC-Link Voltage:  Vdc,peak = %.1f V (Boost Factor B = %.2f)\n', mean_Vdc_pk, mean_B);
fprintf('Grid Injected Active Power:%.2f kW (Inverter Efficiency = %.1f %%)\n', mean_Pgrid/1e3, eff_inverter);
fprintf('Grid Reactive Power:       %.2f var (Power Factor = %.4f)\n', mean_Qgrid, mean_PF);
fprintf('===================================================================\n');

%% Plotting Comprehensive Case 1 Results
fig = figure('Name', 'Case 1 - STC Validation', 'Color', 'w', 'Position', [100, 80, 1100, 820]);

% Subplot 1: PV Active Power vs True Maximum Power
subplot(4, 1, 1);
plot(res.time, res.Pmax_true/1e3, 'k--', 'LineWidth', 1.8, 'DisplayName', 'Theoretical P_{max} (STC)');
hold on;
plot(res.time, res.Ppv/1e3, 'Color', [0.85, 0.33, 0.1], 'LineWidth', 2.0, 'DisplayName', 'Tracked P_{pv} (Current Sweep)');
% Highlight sweep intervals
sweep_regions = res.mppt_state == 1;
yl = [0, 12];
ylim(yl);
grid on; box on;
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
ylabel('Power (kW)', 'FontSize', 10, 'FontWeight', 'bold');
title('(a) PV Array Active Power Tracking at STC (1000 W/m^2, 25^\circC)', 'FontSize', 11, 'FontWeight', 'bold');
legend('Location', 'southeast', 'FontSize', 9);

% Subplot 2: PV Voltage and Current
subplot(4, 1, 2);
yyaxis left;
plot(res.time, res.Vpv, 'b-', 'LineWidth', 1.8);
ylabel('PV Voltage V_{pv} (V)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([0, 500]);
grid on; box on;
yyaxis right;
plot(res.time, res.Ipv, 'r-', 'LineWidth', 1.8);
ylabel('PV Current I_{pv} (A)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([0, 35]);
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
title('(b) PV Terminal Voltage and Current Dynamics', 'FontSize', 11, 'FontWeight', 'bold');

% Subplot 3: ZSI Network Boost and DC-Link Voltage
subplot(4, 1, 3);
plot(res.time, res.Vdc_peak, 'm-', 'LineWidth', 1.8, 'DisplayName', 'Bridge Peak DC Voltage V_{dc,peak}');
hold on;
plot(res.time, res.Vc, 'c-', 'LineWidth', 1.8, 'DisplayName', 'Z-Capacitor Voltage V_C');
yline(622.3, 'k:', 'LineWidth', 1.5, 'DisplayName', 'Minimum Peak AC Grid Line-to-Line (622V)');
ylim([200, 1100]);
grid on; box on;
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
ylabel('Voltage (V)', 'FontSize', 10, 'FontWeight', 'bold');
title('(c) Z-Source Inverter (ZSI) DC-Link Boost Realization', 'FontSize', 11, 'FontWeight', 'bold');
legend('Location', 'southeast', 'FontSize', 9);

% Subplot 4: Grid Injected Waveforms (Zoomed In at Steady State)
subplot(4, 1, 4);
zoom_idx = res.time >= 1.50 & res.time <= 1.56; % 3 grid cycles (50 Hz, 20ms/cycle)
t_zoom = (res.time(zoom_idx) - 1.50) * 1e3; % in ms
yyaxis left;
plot(t_zoom, res.vga(zoom_idx), 'b-', 'LineWidth', 1.8);
ylabel('Grid Voltage v_{ga} (V)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([-450, 450]);
grid on; box on;
yyaxis right;
plot(t_zoom, res.iga(zoom_idx), 'r-', 'LineWidth', 2.0);
ylabel('Grid Current i_{ga} (A)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([-40, 40]);
xlabel('Time (ms) [Zoom: 3 Grid Cycles at 50 Hz]', 'FontSize', 10, 'FontWeight', 'bold');
title('(d) Steady-State Grid Phase-A Voltage & Current (In-Phase Unity Power Factor)', 'FontSize', 11, 'FontWeight', 'bold');

% Save high-resolution figure
saveas(fig, 'case1_stc_results.png');
fprintf('Saved figure to case1_stc_results.png\n');
