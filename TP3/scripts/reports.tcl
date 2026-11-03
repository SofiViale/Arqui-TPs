report_utilization -file [file join $build utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $build timing.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $build critical_setup.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $build critical_hold.rpt]
report_drc -file [file join $build drc.rpt]
report_cdc -file [file join $build cdc.rpt]
check_timing -verbose -file [file join $build check_timing.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]==0 || [llength $hold]==0} {error "No constrained timing paths"}
if {[get_property SLACK $setup]<0 || [get_property SLACK $hold]<0} {error "Timing failed; bitstream withheld, inspect reports"}
write_checkpoint -force [file join $build routed.dcp]
write_bitstream -force [file join $build tp3.bit]
exit 0
