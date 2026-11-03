source [file join [file dirname [info script]] sources.tcl]
set build [file join $tp3 build vivado]
file mkdir $build
create_project -force tp3 [file join $build project] -part xc7a35tcpg236-1
add_files -norecurse $sources
set_property include_dirs [list [file join $tp3 rtl]] [current_fileset]
set_property top tp3_basys3_top [current_fileset]
add_files -fileset constrs_1 -norecurse [file join $tp3 constraints basys3.xdc]
update_compile_order -fileset sources_1
if {[llength $argv] && [lindex $argv 0] eq "project"} {exit 0}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
source [file join $tp3 scripts reports.tcl]
