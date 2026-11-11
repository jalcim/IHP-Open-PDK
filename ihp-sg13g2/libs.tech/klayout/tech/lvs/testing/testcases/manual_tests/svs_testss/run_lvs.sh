#!/bin/bash
# ==============================================================
# Run manual SVS regression (netlist against netlist, no layout).
#
# Each case declares the verdict it expects and the script fails if a
# case does not behave that way.
#
# Three verdicts are possible. PASS and FAIL are the two comparison
# outcomes. ERROR means the netlist reader rejected a netlist: the run
# aborts before the comparison, so there is no verdict. The reader
# does this for a ptap1/ntap1 tap whose node count is not two.
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_LVS="${SCRIPT_DIR}/../../../../run_lvs.py"
MASTER_NETLIST="${SCRIPT_DIR}/svs_master_inv.cdl"
RUN_ROOT="${TMPDIR:-/tmp}/sg13g2_svs_testss_$(date +%Y_%m_%d_%H_%M_%S)"

FAILED=0

run_case() {
  local case_name="$1"
  local schematic="$2"
  local layout_netlist="$3"
  local topcell="$4"
  local expected="$5"
  local case_dir="${RUN_ROOT}/${case_name}"
  local case_log="${case_dir}/${case_name}.log"

  mkdir -p "${case_dir}"

  echo "Running ${case_name} (expected: ${expected})"
  python3 "${RUN_LVS}" \
    --topcell="${topcell}" \
    --netlist="${schematic}" \
    --layout_netlist="${layout_netlist}" \
    --run_mode=deep \
    --run_dir="${case_dir}" > "${case_log}" 2>&1 || true

  local actual="UNKNOWN"
  if grep -q "Congratulations! Netlists match." "${case_log}"; then
    actual="PASS"
  elif grep -q "ERROR : Netlists don't match" "${case_log}"; then
    actual="FAIL"
  elif grep -q "needs 2 nodes (TIE WELL)" "${case_log}"; then
    actual="ERROR"
  fi

  if [[ "${actual}" == "${expected}" ]]; then
    echo "  -> ${case_name}: OK (actual=${actual})"
  else
    echo "  -> ${case_name}: UNEXPECTED (actual=${actual}, expected=${expected})"
    FAILED=$((FAILED + 1))
  fi
}

run_case "1_pass_match" "${MASTER_NETLIST}" "${SCRIPT_DIR}/svs_layout_match.cdl" "svs_inv" "PASS"
run_case "2_fail_connection" "${MASTER_NETLIST}" "${SCRIPT_DIR}/svs_layout_conn_fail.cdl" "svs_inv" "FAIL"
run_case "3_fail_parameter" "${MASTER_NETLIST}" "${SCRIPT_DIR}/svs_layout_param_fail.cdl" "svs_inv" "FAIL"

# --- ptap1/ntap1 taps written as subcircuit calls (X form) -----------------
# The reference is the same taps in R form, the form the layout netlist
# writer produces.

# X-form taps as in the IO CDLs, with the " / " separator and with Perim=.
run_case "4_pass_tap_xform" \
  "${SCRIPT_DIR}/svs_tap_xform.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "PASS"

# An X-form tap inside a user subcircuit whose name starts with "ptap1":
# the subcircuit stays hierarchy, its tap is read as a tap.
run_case "5_pass_tap_xform_hier" \
  "${SCRIPT_DIR}/svs_tap_xform_hier.cdl" "${SCRIPT_DIR}/svs_tap_rform_hier.cdl" "svs_tap" "PASS"

# TIE and WELL are not interchangeable. The swapped tap shares VDD with
# another tap, so renaming nets cannot absorb the swap.
run_case "6_fail_tap_swapped_nodes" \
  "${SCRIPT_DIR}/svs_tap_xform_swapped.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "FAIL"

# An ntap1 is not a ptap1.
run_case "7_fail_tap_polarity" \
  "${SCRIPT_DIR}/svs_tap_xform_polarity.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "FAIL"

# P=3.16 without a unit is 3.16 m, not 3.16 um.
run_case "8_fail_tap_unitless_p" \
  "${SCRIPT_DIR}/svs_tap_xform_unitless_p.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "FAIL"

# A tap needs exactly two nodes, TIE then WELL.
run_case "9_error_tap_xform_1node" \
  "${SCRIPT_DIR}/svs_tap_xform_1node.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "ERROR"
run_case "10_error_tap_xform_3nodes" \
  "${SCRIPT_DIR}/svs_tap_xform_3nodes.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "ERROR"

# Same for the R form, once the tap device class already exists: the
# third node used to be dropped silently.
run_case "11_error_tap_rform_3nodes" \
  "${SCRIPT_DIR}/svs_tap_rform_3nodes.cdl" "${SCRIPT_DIR}/svs_tap_rform.cdl" "svs_tap" "ERROR"

if [[ "${FAILED}" -ne 0 ]]; then
  echo "SVS regression FAILED (${FAILED} case(s) mismatched expected outcome)."
  echo "Logs: ${RUN_ROOT}"
  exit 1
fi

echo "SVS regression PASSED (all cases as expected)."
echo "Logs: ${RUN_ROOT}"
