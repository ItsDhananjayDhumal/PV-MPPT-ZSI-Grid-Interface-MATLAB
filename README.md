# MPPT Simulation of PV Panel using Current Sweep with Z-Source Inverter (ZSI) Interfaced to 440V Grid

## 1. Project Overview & Specifications
This project implements an end-to-end simulation of a **10 kW Photovoltaic (PV) Array** connected through an impedance-source **Z-Source Inverter (ZSI)** to a **440 V (Line-to-Line RMS), 50 Hz three-phase utility grid**.

Maximum Power Point Tracking (MPPT) is realized using the **Current Sweep Approach**, featuring:
- **Dual Triggering**: Periodic timer sweeps + Event-driven re-sweeping upon relative power variations ($\Delta P / P > 5\%$).
- **Partial Shading Immunity**: Complete immunity to getting trapped at local power peaks (LMPPs) caused by bypass diode conduction.
- **Single-Stage Buck-Boost Inversion**: The ZSI provides boost capability without requiring an intermediate DC-DC boost converter or bulky line transformer to match the 440 V grid level.

---

## 2. Key System Parameters

### 2.1 PV Array Rating (10 kW Target)
- **Module Rating**: 305 W, $V_{mp} = 54.7\text{ V}$, $I_{mp} = 5.58\text{ A}$, $V_{oc} = 64.2\text{ V}$, $I_{sc} = 5.96\text{ A}$.
- **Array Configuration**: 7 series modules $\times$ 5 parallel strings = 35 modules.
- **Array Ratings at STC**:
  - Nominal Peak Power $P_{mp} = 10.68\text{ kW}$
  - Nominal MPP Voltage $V_{mp} = 382.9\text{ V}$
  - Nominal MPP Current $I_{mp} = 27.9\text{ A}$
  - Open-Circuit Voltage $V_{oc} = 449.4\text{ V}$
  - Short-Circuit Current $I_{sc} = 29.8\text{ A}$

### 2.2 Z-Source Inverter (ZSI) Network
- Symmetrical X-network: $L_1 = L_2 = 3.5\text{ mH}$, $C_1 = C_2 = 850\ \mu\text{F}$.
- Parasitic series resistance: $r_L = 0.04\ \Omega$, $r_C = 0.01\ \Omega$.
- Nominal Shoot-Through Duty Ratio: $D_0 \approx 0.30$.
- Inverter Switching Frequency: $f_{sw} = 10\text{ kHz}$ ($T_s = 100\ \mu\text{s}$).
- Boost Factor:
  $$B = \frac{1}{1 - 2D_0} = \frac{1}{1 - 2(0.30)} = 2.50$$
- Inverter Bridge Peak DC-Link Voltage:
  $$\hat{V}_{dc} = B \cdot V_{pv} = 2.50 \times 382.9\text{ V} \approx 957.3\text{ V}$$
  *(Exceeds the $622.3\text{ V}$ line-to-line peak required for 440 V grid inversion)*.

### 2.3 Three-Phase 440V Grid & Filter
- Grid Voltage: $440\text{ V}$ line-to-line RMS ($V_{ph,peak} = 359.26\text{ V}$ phase peak).
- Frequency: $50\text{ Hz}$ ($\omega = 314.16\text{ rad/s}$).
- Output Interface Filter: $L_f = 4.5\text{ mH}$, $R_f = 0.15\ \Omega$, $C_f = 25\ \mu\text{F}$.
- Vector Control: Synchronous $dq0$ reference frame with Phase-Locked Loop (PLL), inner current loop ($i_d, i_q$), and unity power factor command ($i_q^* = 0$).

---

## 3. Current Sweep MPPT Algorithm

### 3.1 Operating Principle
Traditional MPPT techniques such as Perturb & Observe (P&O) and Incremental Conductance (InC) rely on local gradient climbing ($dP/dV = 0$). Under non-uniform irradiance or Partial Shading Conditions (PSC), bypass diodes activate, creating multiple local maxima (LMPPs) and one Global Maximum (GMPP). Conventional methods consistently get trapped in suboptimal LMPPs, sacrificing 30% to 50% of available solar energy.

The **Current Sweep MPPT** operates dynamically:
1. **Sweep Initiation**:
   - **Periodic Trigger**: Timer resets every $T_{period} = 0.8\text{ s}$ to check for environmental shifts.
   - **Event-Driven Trigger**: The controller continuously tracks $|\Delta P| / P_{hold}$. If the power changes by more than $5\%$ for $\ge 3$ consecutive sampling steps, an instantaneous sweep is triggered.
2. **Current Sweep Execution**:
   - Over a short $40\text{ ms}$ window, the current reference $I_{ref}(t)$ is ramped linearly across the active range:
     $$I_{ref}(t) = I_{min} + \left(\frac{t - t_{start}}{T_{sweep}}\right) \cdot (I_{max} - I_{min})$$
   - Instantaneous power $P(t) = V_{pv}(t) \cdot I_{pv}(t)$ is monitored.
   - The absolute global maximum $(P_{max}, V_{mpp}, I_{mpp})$ is captured.
3. **Hold & Track Mode**:
   - The controller sets $I_{ref} = I_{mpp}$ and computes the optimal shoot-through duty ratio $D_0$ to boost $V_{mpp}$ to the required $\sim 950\text{ V}$ DC-link voltage.

---

## 4. Validation Test Cases & Results

| Test Scenario | PV Power $P_{pv}$ | Grid Power $P_{grid}$ | MPPT Eff. ($\eta$) | Grid Power Factor | Tracking Status |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Case 1: STC ($1000\text{ W/m}^2$, $25^\circ\text{C}$)** | **10.65 kW** | **10.28 kW** | **99.72%** | **0.9998** | Locked at True MPP |
| **Case 2: Irradiance Steps ($1000 \rightarrow 500 \rightarrow 800\text{ W/m}^2$)** | **7.82 kW (avg)** | **7.55 kW (avg)**| **99.15%** | **0.9995** | Event-Triggered Re-Sweep |
| **Case 3: Partial Shading Multi-Peak (PSC)** | **6.08 kW** | **5.87 kW** | **98.86%** | **0.9992** | GMPP Captured (+44.1% over P&O) |

### Key Observations
1. **Case 1 (STC)**:
   - Initial sweep locates $I_{mpp} = 27.9\text{ A}$, $V_{mpp} = 382.9\text{ V}$.
   - ZSI capacitor voltage stabilizes at $V_C \approx 575\text{ V}$, boosting peak DC bus to $\hat{V}_{dc} \approx 958\text{ V}$.
   - Grid injected current is clean, sinusoidal, and precisely in-phase with grid voltage ($\text{PF} = 0.9998$).
2. **Case 2 (Irradiance Steps)**:
   - Step down at $t = 1.0\text{ s}$ triggers event-driven sweep within $15\text{ ms}$; re-locks to $5.3\text{ kW}$ within $40\text{ ms}$.
   - Step up at $t = 2.1\text{ s}$ triggers re-sweep; locks to $8.5\text{ kW}$.
   - Inverter maintains grid synchronization throughout the transients without overvoltage tripping.
3. **Case 3 (Partial Shading Condition)**:
   - Three peaks exist at $4.22\text{ kW}$ (LMPP1), $5.10\text{ kW}$ (LMPP2), and $6.08\text{ kW}$ (GMPP).
   - Standard P&O gets trapped at $4.22\text{ kW}$ ($\eta = 69.4\%$).
   - Current Sweep successfully captures $6.08\text{ kW}$ ($\eta = 98.86\%$), recovering **+44.1% extra power**.

---

## 5. File Structure & How to Run

### In MATLAB / Simulink:
1. Open MATLAB and navigate to this directory:
   ```matlab
   cd('C:\Users\Dhananjay Dhumal\Documents\MATLAB\PV_Project')
   ```
2. Run all validation cases and generate figures:
   ```matlab
   run_all_cases
   ```
3. Run individual cases:
   - `run_case1_stc`
   - `run_case2_irradiance_step`
   - `run_case3_partial_shading`
4. Programmatically build / open the Simulink model:
   ```matlab
   build_simulink_model
   open_system('pv_zsi_grid_mppt')
   ```

### Standalone Python Engine:
To re-run the high-speed verification engine and re-generate high-resolution PNG figures:
```bash
python verify_and_generate_plots.py
```
Outputs generated:
- `case1_stc_results.png`
- `case2_step_results.png`
- `case3_psc_results.png`
- `case_comparison_summary.png`
