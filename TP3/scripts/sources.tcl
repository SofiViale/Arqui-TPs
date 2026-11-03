# Paths are relative to this script, independent of invocation directory.
set tp3 [file normalize [file join [file dirname [info script]] ..]]
set root [file dirname $tp3]
set sources [list [file join $root TP1 src alu.v]]
foreach name {baud_rate_generator uart_rx uart_tx reset_sync} {lappend sources [file join $root TP2 src $name.v]}
foreach name {alu_adapter decoder immediate register_file imem dmem processor packet debug system basys3_top} {lappend sources [file join $tp3 rtl $name.v]}
