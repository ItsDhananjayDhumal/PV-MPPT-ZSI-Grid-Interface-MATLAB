function res = run_case2_irradiance_step()
% =========================================================================
% run_case2_irradiance_step.m
% =========================================================================
% Case 2: Rapid Irradiance Step Changes (1000 -> 500 -> 800 W/m^2)
%
% Validates:
% 1. Event-driven triggering upon sudden environmental irradiance variation.
% 2. Re-sweep responsiveness, tracking speed, and recovery stability.
% 3. ZSI voltage boost adaptation under varying PV input voltage.
% 4. Continuous grid power feeding without inverter trip or loss of sync.
% =========================================================================

fprintf('===================================================================\n');
fprintf('RUNNING CASE 2: Rapid Irradiance Step Changes\n');
fprintf('===================================================================\n');

% Run the simulation
res = pv_zsi_grid_sim(2);

% Evaluate tracking metrics in the three distinct irradiance regimes
idx_reg1 = res.time >= 0.3 & res.time < 0.95 & res.mppt_state == 2;
idx_reg2 = res.time >= 1.2 & res.time < 2.05 & res.mppt_state == 2;
idx_reg3 = res.time >= 2.3 & res.time < 3.15 & res.mppt_state == 2;

Ppv_1 = mean(res.Ppv(idx_reg1)); Pmax_1 = mean(res.Pmax_true(idx_reg1));
Ppv_2 = mean(res.Ppv(idx_reg2)); Pmax_2 = mean(res.Pmax_true(idx_reg2));
Ppv_3 = mean(res.Ppv(idx_reg3)); Pmax_3 = mean(res.Pmax_true(idx_reg3));

fprintf('--- Case 2 Key Performance Metrics ---\n');
fprintf('Regime 1 (1000 W/m^2): Ppv = %.2f kW / %.2f kW (Eff = %.2f %%)\n', Ppv_1/1e3, Pmax_1/1e3, (Ppv_1/Pmax_1)*100);
fprintf('Regime 2 ( 500 W/m^2): Ppv = %.2f kW / %.2f kW (Eff = %.2f %%)\n', Ppv_2/1e3, Pmax_2/1e3, (Ppv_2/Pmax_2)*100);
fprintf('Regime 3 ( 800 W/m^2): Ppv = %.2f kW / %.2f kW (Eff = %.2f %%)\n', Ppv_3/1e3, Pmax_3/1e3, (Ppv_3/Pmax_3)*100);
fprintf('Overall Dynamic Tracking Efficiency: %.2f %%\n', res.tracking_eff);
fprintf('===================================================================\n');

%% Plotting Comprehensive Case 2 Results
fig = figure('Name', 'Case 2 - Dynamic Irradiance Step Validation', 'Color', 'w', 'Position', [100, 80, 1100, 820]);

% Subplot 1: Irradiance Profile and MPPT Controller State
subplot(4, 1, 1);
yyaxis left;
plot(res.time, res.G, 'Color', [0.9, 0.6, 0.0], 'LineWidth', 2.0);
ylabel('Irradiance G (W/m^2)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([300, 1200]);
grid on; box on;
yyaxis right;
stairs(res.time, res.mppt_state, 'Color', [0.2, 0.6, 0.2], 'LineWidth', 1.8);
ylabel('MPPT State (1=Sweep, 2=Hold)', 'FontSize', 9, 'FontWeight', 'bold');
ylim([0.8, 2.4]);
yticks([1, 2]);
yticklabels({'SWEEPING', 'HOLD/TRACK'});
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
title('(a) Environmental Irradiance Steps and MPPT Trigger Responses', 'FontSize', 11, 'FontWeight', 'bold');

% Subplot 2: PV Power Tracking with Event Triggers Highlighted
subplot(4, 1, 2);
plot(res.time, res.Pmax_true/1e3, 'k--', 'LineWidth', 1.8, 'DisplayName', 'Theoretical P_{max}');
hold on;
plot(res.time, res.Ppv/1e3, 'Color', [0.85, 0.33, 0.1], 'LineWidth', 2.0, 'DisplayName', 'Tracked PV Power P_{pv}');
xline(1.0, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Step Down (1000 \rightarrow 500 W/m^2)');
xline(2.1, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Step Up (500 \rightarrow 800 W/m^2)');
ylim([0, 12]);
grid on; box on;
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
ylabel('Power (kW)', 'FontSize', 10, 'FontWeight', 'bold');
title('(b) PV Power Dynamic Response & Event-Driven Re-Sweep Convergence', 'FontSize', 11, 'FontWeight', 'bold');
legend('Location', 'northeast', 'FontSize', 9);

% Subplot 3: PV Terminal Voltage and Current
subplot(4, 1, 3);
yyaxis left;
plot(res.time, res.Vpv, 'b-', 'LineWidth', 1.8);
ylabel('PV Voltage V_{pv} (V)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([0, 480]);
grid on; box on;
yyaxis right;
plot(res.time, res.Ipv, 'r-', 'LineWidth', 1.8);
ylabel('PV Current I_{pv} (A)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([0, 35]);
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
title('(c) PV Terminal Operating Point Migration', 'FontSize', 11, 'FontWeight', 'bold');

% Subplot 4: ZSI Peak DC-Link Voltage and Grid Injected Power
subplot(4, 1, 4);
yyaxis left;
plot(res.time, res.Vdc_peak, 'm-', 'LineWidth', 1.8);
ylabel('Peak DC Bus V_{dc,peak} (V)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([400, 1100]);
grid on; box on;
yyaxis right;
plot(res.time, res.Pgrid/1e3, 'Color', [0.0, 0.5, 0.0], 'LineWidth', 2.0);
ylabel('Grid Active Power P_{grid} (kW)', 'FontSize', 10, 'FontWeight', 'bold');
ylim([0, 12]);
xlabel('Time (s)', 'FontSize', 10, 'FontWeight', 'bold');
title('(d) ZSI Impedance Network Stability & Continuous Grid Power Delivery', 'FontSize', 11, 'FontWeight', 'bold');

% Save high-resolution figure
saveas(fig, 'case2_step_results.png');
fprintf('Saved figure to case2_step_results.png\n');
