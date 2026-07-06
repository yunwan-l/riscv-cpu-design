## =============================================================================
## create_project.tcl - RVP Vivado Project Creation Script
## =============================================================================
## Creates a Vivado project for the RVP (RISC-V Pipeline) processor, adds all
## RTL source files (read from config/rvp_core.f), adds the board constraints,
## sets compile-time configuration defines, and targets a specific FPGA device.
##
## Usage (from Vivado Tcl console or batch mode):
##   vivado -mode batch -source synth/vivado/create_project.tcl \
##          -tclargs [options]
##
## Options (all optional, defaults shown):
##   -project_name  rvp_nexys4        Vivado project name
##   -project_dir  build/vivado       Output directory for the project
##   -board        nexys4             Target board: nexys4 | zybo
##   -config       phase2_full_rv32i  Named config from config/rvp_configs.yaml
##   -top          rvp_core           Top-level module name
##
## Example:
##   vivado -mode batch -source create_project.tcl \
##          -tclargs -board nexys4 -config phase3_icache_lru
## =============================================================================

# -----------------------------------------------------------------------------
# Parse command-line arguments
# -----------------------------------------------------------------------------
set project_name  "rvp_nexys4"
set project_dir   "build/vivado"
set board         "nexys4"
set config_name   "phase2_full_rv32i"
set top_module    "rvp_core"

if { [llength $argv] > 0 } {
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set arg [lindex $argv $i]
        switch -- $arg {
            -project_name { incr i; set project_name [lindex $argv $i] }
            -project_dir  { incr i; set project_dir  [lindex $argv $i] }
            -board        { incr i; set board         [lindex $argv $i] }
            -config       { incr i; set config_name  [lindex $argv $i] }
            -top          { incr i; set top_module    [lindex $argv $i] }
            default {
                puts "WARNING: Unknown argument '$arg'"
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Resolve paths (project root is two levels up from this script)
# -----------------------------------------------------------------------------
set script_dir  [file dirname [info script]]
set project_root [file normalize [file join $script_dir .. ..]]

set filelist_path [file join $project_root "config" "rvp_core.f"]
set config_svh    [file join $project_root "config" "rvp_config.svh"]
set configs_yaml [file join $project_root "config" "rvp_configs.yaml"]

puts "============================================================================="
puts " RVP Vivado Project Creation"
puts "============================================================================="
puts " Project root : $project_root"
puts " Project name : $project_name"
puts " Project dir  : $project_dir"
puts " Board         : $board"
puts " Config        : $config_name"
puts " Top module    : $top_module"
puts " File list    : $filelist_path"
puts "============================================================================="

# -----------------------------------------------------------------------------
# Select target part based on board
# -----------------------------------------------------------------------------
switch -- $board {
    nexys4 {
        # NEXYS4 / NEXYS4 DDR (Artix-7 100T)
        set part "xc7a100tcsg324-1"
        set xdc_file [file join $script_dir "rvp_nexys4.xdc"]
    }
    zybo {
        # Zybo Zynq-7020
        set part "xc7z020clg400-1"
        set xdc_file [file join $script_dir "rvp_zybo.xdc"]
    }
    default {
        puts "ERROR: Unknown board '$board'. Use 'nexys4' or 'zybo'."
        exit 1
    }
}
puts " Target part  : $part"
puts " Constraints  : $xdc_file"
puts "============================================================================="

# -----------------------------------------------------------------------------
# Build compile-time defines string from YAML config
# We use a simple Tcl parser for the flat YAML structure in rvp_configs.yaml.
# -----------------------------------------------------------------------------
proc parse_config_yaml {yaml_path config_name} {
    if {![file exists $yaml_path]} {
        puts "ERROR: Config YAML not found: $yaml_path"
        exit 1
    }

    set fh [open $yaml_path r]
    set lines [split [read $fh] "\n"]
    close $fh

    set in_config 0
    set result [dict create]

    foreach line $lines {
        # Skip blank lines and comments
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
            continue
        }

        # Detect config section header (no leading space, ends with ':')
        if {![regexp {^\s} $line] && [regexp {^([\w]+):\s*$} $line -> name]} {
            set in_config [expr {$name eq $config_name}]
            continue
        }

        if {$in_config} {
            # Key: value  (allow quoted or unquoted values)
            if {[regexp {^\s*([A-Za-z_]\w*)\s*:\s*(.+?)\s*$} $line -> key val]} {
                # Strip inline comments
                regsub {\s+#.*$} $val "" val
                # Strip surrounding quotes
                set val [string trim $val "\"' "]
                dict set result $key $val
            }
        }
    }

    if {[dict size $result] == 0} {
        puts "ERROR: Configuration '$config_name' not found in $yaml_path"
        exit 1
    }

    return $result
}

set config_params [parse_config_yaml $configs_yaml $config_name]
puts " Configuration parameters:"
dict for {k v} $config_params {
    puts "   $k = $v"
}
puts "============================================================================="

# Map YAML config keys to Verilog define names (RVP_<KEY>)
set define_list [list]
dict for {key val} $config_params {
    set def_name "RVP_${key}"
    lappend define_list "${def_name}=${val}"
}

# Always include the config header path so rvp_config.svh is found
set include_dirs [file join $project_root "config"]

# -----------------------------------------------------------------------------
# Create the Vivado project
# -----------------------------------------------------------------------------
set full_project_dir [file join $project_root $project_dir]

# Create output directory if it doesn't exist
file mkdir [file dirname $full_project_dir]

# Close any open project
close_project -quiet

# Create project
create_project $project_name $full_project_dir -part $part -force

# Set project properties
set_property target_language Verilog     [current_project]
set_property simulator_language Mixed    [current_project]
set_property default_lib       xil_defaultlib [current_project]

# -----------------------------------------------------------------------------
# Read the file list (config/rvp_core.f) and add RTL sources
# -----------------------------------------------------------------------------
if {![file exists $filelist_path]} {
    puts "ERROR: File list not found: $filelist_path"
    exit 1
}

set fh [open $filelist_path r]
set filelist_lines [split [read $fh] "\n"]
close $fh

set added_files [list]

foreach line $filelist_lines {
    set trimmed [string trim $line]
    # Skip blank lines
    if {$trimmed eq ""} {
        continue
    }
    # Skip lines that are comments (start with // or #)
    if {[regexp {^\s*(//|#)} $line]} {
        continue
    }

    set src_path [file join $project_root $trimmed]
    if {[file exists $src_path]} {
        lappend added_files $src_path
        add_files -norecurse $src_path
        puts "  Added: $trimmed"
    } else {
        puts "  WARNING (skipped, file not found): $trimmed"
    }
}

# Set file type to SystemVerilog for .sv files
foreach f $added_files {
    set ext [file extension $f]
    if {$ext eq ".sv" || $ext eq ".svh"} {
        set_property file_type SystemVerilog [get_files $f]
    }
}

# -----------------------------------------------------------------------------
# Add the config header as a global include
# -----------------------------------------------------------------------------
if {[file exists $config_svh]} {
    add_files -norecurse $config_svh
    set_property file_type {Verilog Header} [get_files $config_svh]
    puts "  Added config header: config/rvp_config.svh"
}

# -----------------------------------------------------------------------------
# Add constraints (XDC)
# -----------------------------------------------------------------------------
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "  Added constraints: [file tail $xdc_file]"
} else {
    puts "  WARNING: Constraints file not found: $xdc_file"
}

# -----------------------------------------------------------------------------
# Apply compile-time defines (Verilog defines) to all source files
# -----------------------------------------------------------------------------
set verilog_define_str [join $define_list " "]
puts "  Verilog defines: $verilog_define_str"

if {$verilog_define_str ne ""} {
    set_property verilog_define $verilog_define_str [get_filesets sources_1]
}

# Add include directory for the config header
set_property include_dirs [list [file join $project_root "config"]] [get_filesets sources_1]

# -----------------------------------------------------------------------------
# Set the top-level module
# -----------------------------------------------------------------------------
set_property top $top_module [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

puts "============================================================================="
puts " Project '$project_name' created successfully."
puts " Location: [file join $full_project_dir ${project_name}.xpr]"
puts "============================================================================="
