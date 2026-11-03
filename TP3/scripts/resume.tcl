# Resume an interrupted implementation only if all synthesized sources are unchanged.
source [file join [file dirname [info script]] sources.tcl]
set build [file join $tp3 build vivado]
set checkpoint [file join $build project tp3.runs synth_1 tp3_basys3_top.dcp]
if {![file exists $checkpoint]} {error "No synthesis checkpoint; run build.tcl"}
foreach path [concat $sources [list [file join $tp3 rtl tp3_defs.vh] [file join $tp3 constraints basys3.xdc]]] {
    if {[file mtime $path] > [file mtime $checkpoint]} {error "Source newer than checkpoint: $path; run build.tcl"}
}
open_project [file join $build project tp3.xpr]
if {[get_property NEEDS_REFRESH [get_runs synth_1]]} {error "Synthesis out of date; run build.tcl"}
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
source [file join $tp3 scripts reports.tcl]
