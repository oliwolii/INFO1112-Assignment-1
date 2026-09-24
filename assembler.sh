#!/bin/bash
#
# Usage:
#   bash assembler.sh <filename.vsc>
#
# Exit codes:
#   0 - success, <filename.bin> produced
#   1 - any error condition (no .bin file produced)


## File must have quit 0,0 at the end 
# file should not have more than 100 lines 
# most of the test files from the spec should fail 
# run via ./assembler.sh file name 

# Assembler only accepts 1 argument: 

if [ "$#" -eq 0 ]; then 
    echo "usage: no argument is provided"
    exit 1
fi

if [ "$#" -gt 1 ]; then
    echo "usage: more than one arguments are provided"
    exit 1
fi

input="$1" # first argument --> file name 


#  The provided arg must exist and be a file 
if [ ! -f "$input" ]; then
    echo "usage: input is not a file or it does not exist"
    exit 1
fi

# The provided arg must have the .vsc extension
# Double bracket --> Regular Expression 
# Single bracket --> Exact match 

if [[ "$input" != *.vsc ]]; then
    echo "usage: input does not have the extension .vsc"
    exit 1
fi

#the output for this should be a bin file and no hardcoding output_file="${input_file%.vsc}.bin"

# Empty file check 

if [ ! -s "$1" ]; then
    echo "usage: the file is empty – no .bin file is produced"
    exit 1
fi



# Read the file into an array of lines
# First line has to be a number between 0 and 2 

lines=()
while IFS= read -r line || [ -n "$line" ]; do.  #r = raw, ifs = set to nothing  
    lines+=("$line")
done < "$input"


# Strip any trailing carriage returns (in case of CRLF line endings)
for i in "${!lines[@]}"; do
    lines[$i]="${lines[$i]%$'\r'}"
done


# -----------------------------------------------------------------------
# Helper: instruction name -> opcode (decimal). Prints -1 for unknown.
# -----------------------------------------------------------------------
get_opcode() {
    case "$1" in
        LOAD)  echo 1 ;;
        STORE) echo 2 ;;
        ADD)   echo 3 ;;
        SUB)   echo 4 ;;
        QUIT)  echo 8 ;;
        PRINT) echo 9 ;;
        *)     echo -1 ;;
    esac
}

# Array holding the bytes (as 2-digit hex strings) to be written, in order.
dataArray=()

# -----------------------------------------------------------------------
# Line 1: must be exactly "0" or "2"
# -----------------------------------------------------------------------
line1="${lines[0]}"

if [[ ! "$line1" =~ ^(0|2)$ ]]; then #regular expression 
    echo "usage: line 1 must be a positive integer - either 0 or 2"
    exit 1
fi

# =========================================================================
# CASE A: line1 == 0  -> the program can only be the sentinel QUIT,0,0
# =========================================================================
if [ "$line1" -eq 0 ]; then

    line2="${lines[1]}"

    if [ "$line2" != "QUIT,0,0" ]; then
        echo "usage: expected the line QUIT,0,0 when line 1 is 0"
        exit 1
    fi

    # opcode 8 (001000) + reg 00 -> byte1 = 00100000 = 0x20
    # memory address 00000000    -> byte2 = 0x00
    # based on the specification given !!! 

    dataArray+=("20")
    dataArray+=("00")

    output="${input%.vsc}.bin"
    rm -f "$output"
    for b in "${dataArray[@]}"; do
        printf "\x$b" >> "$output"
    done

    echo "It is a QUIT program"
    echo "The content of the .bin file is"
    # need cat "$output_file"
    # printing cannot be printing 2000, but 20 in one row and 00 in the other row use -c1 
    xxd -p -c1 "$output"
    exit 0
fi


# CASE B: line1 == 2  -> static values + ADD/SUB style program
#at least 3 lines (implement)
# line 1 = 2
#line 2 = data 
#line 3 = data 

# --- Static data values (Line 2 and Line 3): each in [0,128) ------------
for idx in 1 2; do
    val="${lines[$idx]}"

    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        echo "usage: line $((idx + 1)) must be a number"
        exit 1
    fi

    numval=$((10#$val))
    if [ "$numval" -lt 0 ] || [ "$numval" -gt 127 ]; then
        echo "usage: line $((idx + 1)) must be in the range 0-127"
        exit 1
    fi

    dataArray+=("$(printf "%02x" "$numval")")
done

# --- Instructions (Line 4 onward) ---------------------------------------
max_instructions=100 #max lines in the file 
instruction_count=0
found_quit=0
total_lines=${#lines[@]}
idx=3


while [ "$idx" -lt "$total_lines" ] && [ "$instruction_count" -lt "$max_instructions" ]; do
    line="${lines[$idx]}"
    idx=$((idx + 1))

    # Skip a single trailing blank line at the end of the file, if present
    if [ -z "$line" ] && [ "$idx" -eq "$total_lines" ]; then
        continue
    fi

    # Maximum valid instruction length is 11 characters (e.g. STORE,2,228) # keep 
    if [ "${#line}" -gt 11 ]; then
        echo "usage: invalid instruction - line too long"
        exit 1
    fi

    # Must have exactly 3 comma-separated fields
    nfields=$(awk -F',' '{print NF}' <<< "$line")
    if [ "$nfields" -ne 3 ]; then
        echo "usage: invalid instruction format"
        exit 1
    fi

# Validating is over Check the Op codes now 

# if [ "$ins" = "LOAD" ] 
#then 
   # opcode="000001"


    IFS=',' read -r ins reg mem <<< "$line"

    opcode=$(get_opcode "$ins")
    if [ "$opcode" -eq -1 ]; then
        echo "usage: unknown instruction $ins"
        exit 1
    fi

    # --- Validate register field (must be 0-3, not empty) ---------------
    if [[ ! "$reg" =~ ^[0-9]+$ ]]; then
        echo "usage: invalid register value"
        exit 1
    fi
    regval=$((10#$reg))
    if [ "$regval" -lt 0 ] || [ "$regval" -gt 3 ]; then
        echo "usage: register value out of range"
        exit 1
    fi

   # CHECKING MEMORY FIELDS KEEP  # --- Validate memory field (must be 0-255, not empty) ----------------
    if [[ ! "$mem" =~ ^[0-9]+$ ]]; then
        echo "usage: invalid memory address value"
        exit 1
    fi
    memval=$((10#$mem))
    if [ "$memval" -lt 0 ] || [ "$memval" -gt 255 ]; then
        echo "usage: memory address value out of range"
        exit 1
    fi

    # QUIT and PRINT always have a fixed 0 memory address field # KEEP 
    if { [ "$ins" == "QUIT" ] || [ "$ins" == "PRINT" ]; } && [ "$memval" -ne 0 ]; then
        echo "usage: $ins must have a memory address of 0"
        exit 1
    fi

    # QUIT always has a fixed 0 register field #If quit isnt 0 then error 
    if [ "$ins" == "QUIT" ] && [ "$regval" -ne 0 ]; then
        echo "usage: QUIT must have a register value of 0"
        exit 1
    fi

    # Build the two bytes: byte1 = opcode(6 bits) . reg(2 bits)
    #                       byte2 = mem(8 bits)
    byte1=$(( opcode * 4 + regval ))
    byte2=$memval

    dataArray+=("$(printf "%02x" "$byte1")")
    dataArray+=("$(printf "%02x" "$byte2")")

    instruction_count=$((instruction_count + 1))

    if [ "$ins" == "QUIT" ]; then
        found_quit=1
        break
    fi
done

#Makes sure the program has a quit 
if [ "$found_quit" -eq 0 ]; then
    echo "usage: program does not contain a QUIT instruction"
    exit 1
fi

# -----------------------------------------------------------------------
# Write out the .bin file (only reached once everything validated OK)
# -----------------------------------------------------------------------


output="${input%.vsc}.bin"
rm -f "$output"
for b in "${dataArray[@]}"; do
    printf "\x$b" >> "$output"
done

echo "It is an ADD/SUB program"
echo "The content of the .bin file is"
xxd -p -c1 "$output"
exit 0
