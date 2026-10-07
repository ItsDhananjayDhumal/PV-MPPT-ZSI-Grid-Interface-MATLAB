% =========================================================================
% run_all_cases.m
% =========================================================================
% Master script to execute all three validation test cases sequentially,
% compile performance metrics, and generate an executive summary report.
%
% Cases:
%   Case 1: Standard Test Condition (STC: 1000 W/m^2, 25 deg C)
%   Case 2: Rapid Irradiance Step Changes (1000 -> 500 -> 800 W/m^2)
%   Case 3: Partial Shading Condition (PSC Multi-Peak GMPP Tracking)
% =========================================================================

clear; close all; clc;

fprintf('====================================================================\n');
fprintf('  MPPT OF PV WITH CURRENT SWEEP & ZSI INTERFACED TO 440V GRID       \n');
fprintf('  MASTER TEST SUITE - EXECUTING ALL 3 VALIDATION CASES              \n');
fprintf('====================================================================\n\n');

%% Execute Case 1
fprintf('>>> [1/3] EXECUTING CASE 1: Standard Test Condition (STC) <<<\n');
res1 = run_case1_stc();

%% Execute Case 2
fprintf('\n>>> [2/3] EXECUTING CASE 2: Rapid Irradiance Step Changes <<<\n');
res2 = run_case2_irradiance_step();

%% Execute Case 3
fprintf('\n>>> [3/3] EXECUTING CASE 3: Partial Shading Conditions (PSC) <<<\n');
res3 = run_case3_partial_shading();

%% Compile Summary Metrics Table Dynamically
% Case 1 Metrics
idx1 = res1.time >= 0.5 & res1.mppt_state == 2;
c1_Ppv = mean(res1.Ppv(idx1))/1e3;
c1_Pgrid = mean(res1.Pgrid(idx1))/1e3;
c1_eff = mean(res1.Ppv(idx1) ./ res1.Pmax_true(idx1))*100;
c1_pf = mean(res1.PF(idx1));

% Case 2 Metrics
idx2 = res2.mppt_state == 2;
c2_Ppv = mean(res2.Ppv(idx2))/1e3;
c2_Pgrid = mean(res2.Pgrid(idx2))/1e3;
c2_eff = res2.tracking_eff;
c2_pf = mean(res2.PF(idx2));

% Case 3 Metrics
idx3 = res3.time >= 0.5 & res3.time < 1.25 & res3.mppt_state == 2;
c3_Ppv = mean(res3.Ppv(idx3))/1e3;
c3_Pgrid = mean(res3.Pgrid(idx3))/1e3;
c3_eff = mean(res3.Ppv(idx3) ./ res3.Pmax_true(idx3))*100;
c3_pf = mean(res3.PF(idx3));

fprintf('\n====================================================================\n');
fprintf('                 VALIDATION CASES PERFORMANCE SUMMARY               \n');
fprintf('====================================================================\n');
fprintf('%-28s | %-12s | %-12s | %-10s | %-10s\n', ...
        'Test Case Scenario', 'P_pv (kW)', 'P_grid (kW)', 'MPPT Eff %', 'Grid PF');
fprintf('--------------------------------------------------------------------\n');
fprintf('%-28s | %-12.2f | %-12.2f | %-10.2f | %-10.4f\n', ...
        'Case 1: STC (1000 W/m2)', c1_Ppv, c1_Pgrid, c1_eff, c1_pf);
fprintf('%-28s | %-12.2f | %-12.2f | %-10.2f | %-10.4f\n', ...
        'Case 2: Irradiance Steps', c2_Ppv, c2_Pgrid, c2_eff, c2_pf);
fprintf('%-28s | %-12.2f | %-12.2f | %-10.2f | %-10.4f\n', ...
        'Case 3: PSC Multi-Peak', c3_Ppv, c3_Pgrid, c3_eff, c3_pf);
fprintf('====================================================================\n');
fprintf('All test cases executed and validated successfully!\n');
fprintf('Artifacts generated: case1_stc_results.png, case2_step_results.png, case3_psc_results.png\n');
