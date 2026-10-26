#!/usr/bin/env python3
"""Simula bloques y pipeline aritmetico de TP3 desde cualquier directorio."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TP3 = ROOT / "TP3"
BUILD = TP3 / "build"
BENCHES = {
    "alu_tb": ["alu_adapter.v"],
    "decode_tb": ["decoder.v", "immediate.v", "alu_adapter.v"],
    "register_file_tb": ["register_file.v"],
    "state_tb": ["state.v"],
    "memory_tb": ["imem.v", "dmem.v"],
    "pipeline_tb": ["core.v", "arithmetic_system.v", "state.v", "imem.v",
                    "decoder.v", "immediate.v", "register_file.v", "alu_adapter.v"],
}


def resolve_tool(value, name):
    if value:
        return shutil.which(value)
    found = shutil.which(name)
    local = BUILD / "tools" / "icarus" / "app" / "bin" / (name + ".exe")
    return found or (str(local) if local.is_file() else None)


def commands(compiler, runtime, bench):
    sources = [TP3 / "rtl" / name for name in BENCHES[bench]]
    if "alu_adapter.v" in BENCHES[bench]:
        sources.insert(0, ROOT / "TP1" / "src" / "alu.v")
    output = BUILD / (bench + ".vvp")
    compile_cmd = [compiler, "-g2005", "-Wall", "-Wno-timescale",
                   "-I", str(TP3 / "rtl"), "-I", str(TP3 / "tb"),
                   "-s", bench, "-o", str(output)]
    compile_cmd += [str(p) for p in sources + [TP3 / "tb" / (bench + ".v")]]
    simulate_cmd = [runtime, str(output)]
    if bench == "pipeline_tb":
        simulate_cmd.append("+TRACE=" + str(BUILD / "pipeline_trace.csv"))
    return compile_cmd, simulate_cmd


def run(command, log, quiet=False):
    print(subprocess.list2cmdline(command), flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                text=True, errors="replace", timeout=60)
        output, code = result.stdout + result.stderr, result.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        output, code = str(error), 1
    log.write_text(output, encoding="utf-8")
    if quiet:
        print(output.splitlines()[0] if output else "(sin salida)")
    else:
        print(output, end="" if output.endswith("\n") else "\n")
    return code, output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", choices=BENCHES)
    parser.add_argument("--stage", choices=["1", "2"], help="Filtrar etapa de desarrollo")
    parser.add_argument("--iverilog")
    parser.add_argument("--vvp")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.bench and args.stage:
        parser.error("usar --bench o --stage, no ambos")
    compiler = resolve_tool(args.iverilog, "iverilog")
    runtime = resolve_tool(args.vvp, "vvp")
    benches = [args.bench] if args.bench else list(BENCHES)
    if args.stage == "1":
        benches = [name for name in BENCHES if name != "pipeline_tb"]
    elif args.stage == "2":
        benches = ["pipeline_tb"]
    if args.list:
        for bench in benches:
            for command in commands(compiler or args.iverilog or "iverilog",
                                    runtime or args.vvp or "vvp", bench):
                print(subprocess.list2cmdline(command))
        return 0
    BUILD.mkdir(parents=True, exist_ok=True)
    results = {}
    if not compiler or not runtime:
        results = {bench: "NOT RUN: faltan iverilog/vvp" for bench in benches}
    else:
        run([compiler, "-V"], BUILD / "iverilog_version.log", quiet=True)
        for bench in benches:
            compile_cmd, simulate_cmd = commands(compiler, runtime, bench)
            code, _ = run(compile_cmd, BUILD / (bench + "_compile.log"))
            if code:
                results[bench] = "FAIL: compilacion"
                continue
            code, output = run(simulate_cmd, BUILD / (bench + ".log"))
            passed = code == 0 and f"PASS: {bench}" in output and "FAIL" not in output
            results[bench] = "PASS" if passed else "FAIL: simulacion"
    report = (f"results_{args.bench}.json" if args.bench else
              f"results_stage_{args.stage}.json" if args.stage else "results.json")
    (BUILD / report).write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))
    return 0 if all(value == "PASS" for value in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
