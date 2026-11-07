open_hw_manager
catch {
    connect_hw_server -allow_non_jtag
    open_hw_target
    set targets [get_hw_targets]
    puts "HW_TARGETS_FOUND: $targets"
    set devices [get_hw_devices]
    puts "HW_DEVICES_FOUND: $devices"
} err
puts "HW_CHECK_RESULT: $err"
close_hw_manager
exit

