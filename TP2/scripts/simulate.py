#!/usr/bin/env python3
"""Run TP2 benches with Icarus; no third-party Python packages required."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "TP2" / "build"
RTL = [ROOT / "TP1" / "src" / "alu.v", *sorted((ROOT / "TP2" / "src").glob("*.v"))]
BENCHES = [
    "baud_rate_generator_tb", "uart_tx_tb", "uart_rx_tb",
    "interface_tb", "tp2_top_tb", "alu_testbench",
]


def tool_path(value):
    found = shutil.which(value)
    return str(Path(found).resolve()) if found else None


def run_logged(command, name):
    print(subprocess.list2cmdline([str(arg) for arg in command]), flush=True)
    try:
        result = subprocess.run(
            command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace", timeout=180,
        )
        output = result.stdout
        returncode = result.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        output = f"FAIL: {error}\n"
        returncode = 1
    (BUILD / f"{name}.log").write_text(output, encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n")
    return returncode, output


def compilation(compiler, bench, nominal=False):
    name = f"{bench}_nominal" if nominal else bench
    testbench = (ROOT / "TP1" / "src" / "alu_testbench.v" if bench == "alu_testbench"
                 else ROOT / "TP2" / "sim" / f"{bench}.v")
    sources = [RTL[0]] if bench == "alu_testbench" else RTL
    # TP1 has no timescale: preserve its source and disable only this warning.
    command = [compiler, "-g2012", "-Wall", "-Wno-timescale", "-I", str(ROOT / "TP2" / "sim"),
               "-s", bench, "-o", str(BUILD / f"{name}.vvp")]
    if nominal:
        command += ["-P", "tp2_top_tb.CLK_FREQ=100000000", "-P", "tp2_top_tb.BAUD_RATE=9600"]
    return command + [str(path) for path in [*sources, testbench]], name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", choices=BENCHES, help="Run only this bench")
    parser.add_argument("--nominal", action="store_true", help="Also run top at 100 MHz / 9600 baud")
    parser.add_argument("--list", action="store_true", help="Print commands without executing or creating files")
    parser.add_argument("--iverilog", default="iverilog", help="Executable name or full path")
    parser.add_argument("--vvp", default="vvp", help="Executable name or full path")
    parser.add_argument("--lint", action="store_true", help="Also check latches/drivers with Yosys (no Vivado)")
    parser.add_argument("--yosys", default="yosys", help="Executable name or full path")
    args = parser.parse_args()
    cases = [(bench, False) for bench in ([args.bench] if args.bench else BENCHES)]
    if args.nominal:
        cases.append(("tp2_top_tb", True))
    if args.list:
        for bench, nominal in cases:
            command, name = compilation(args.iverilog, bench, nominal)
            print(subprocess.list2cmdline(command))
            print(subprocess.list2cmdline([args.vvp, str(BUILD / f"{name}.vvp")]))
        if args.lint:
            print(f"{args.yosys} -s TP2/build/check.ys (generated when executing --lint)")
        return 0

    BUILD.mkdir(parents=True, exist_ok=True)
    compiler, runtime = tool_path(args.iverilog), tool_path(args.vvp)
    results = {}
    if not compiler or not runtime:
        missing = [value for value, found in [(args.iverilog, compiler), (args.vvp, runtime)] if not found]
        print("NOT RUN: missing executable(s): " + ", ".join(missing))
        print("Install Icarus Verilog separately or pass --iverilog and --vvp with full paths.")
        for bench, nominal in cases:
            results[bench + ("_nominal" if nominal else "")] = "NOT RUN: missing Icarus Verilog"
    else:
        for bench, nominal in cases:
            command, name = compilation(compiler, bench, nominal)
            status, _ = run_logged(command, f"{name}_compile")
            if status:
                results[name] = "FAIL: compilation"
                continue
            status, output = run_logged([runtime, str(BUILD / f"{name}.vvp")], name)
            marker = "ALU Testbench completed successfully." if bench == "alu_testbench" else "PASS:"
            passed = status == 0 and marker in output and "FAIL" not in output and "failed" not in output
            results[name] = "PASS" if passed else "FAIL: simulation or missing success marker"

    if args.lint:
        yosys = tool_path(args.yosys)
        if not yosys:
            results["structural_check"] = "NOT RUN: missing Yosys"
        else:
            source_list = " ".join('"' + path.relative_to(ROOT).as_posix() + '"' for path in RTL)
            script = "\n".join([
                "read_verilog " + source_list,
                "hierarchy -check -top tp2_top",
                "proc", "opt", "check -assert",
                "select -assert-none t:$dlatch t:$adlatch t:$dlatchsr",
                "stat", "",
            ])
            (BUILD / "check.ys").write_text(script, encoding="utf-8")
            status, _ = run_logged([yosys, "-s", str(BUILD / "check.ys")], "structural_check")
            results["structural_check"] = "PASS" if status == 0 else "FAIL: structural check"

    (BUILD / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print("\nResults:")
    for name, status in results.items():
        print(f"  {name}: {status}")
    return 0 if all(status == "PASS" for status in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
