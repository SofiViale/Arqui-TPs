set tp3 [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $tp3 build vivado tp3.bit]
if {[llength $argv]} {set bit [file normalize [lindex $argv 0]]}
if {![file exists $bit]} {error "Bitstream not found: $bit"}
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices -filter {PART =~ xc7a35t*}]
if {[llength $devices]!=1} {error "Expected exactly one Basys 3 xc7a35t device"}
set dev [lindex $devices 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
close_hw_manager
exit 0
