#!/bin/zsh

# --- Configuration ---
OUTPUT_DIR="./countries"
FAVORITES_FILE="./Favorites.m3u"
INPUT_FILE=${1:-"tv_channels_4b1b8d4db83e_plus.m3u"}

# --- Visual Enhancement Settings ---
if command -v tput >/dev/null 2>&1; then
    TERMINAL_WIDTH=$(tput cols)
    TERMINAL_HEIGHT=$(tput lines)
else
    TERMINAL_WIDTH=80; TERMINAL_HEIGHT=24
fi
(( TERMINAL_WIDTH < 50 )) && TERMINAL_WIDTH=50
(( TERMINAL_HEIGHT < 15 )) && TERMINAL_HEIGHT=15

C_RESET="%f%b%k"; C_BORDER="%F{cyan}"; C_TITLE="%B%F{yellow}"
C_OPTION="%F{green}"; C_OPTION_TEXT="%f"; C_PROMPT="%F{blue}"
C_ERROR="%B%F{red}"; C_INFO="%F{cyan}"; C_WARN="%F{yellow}"
C_SUCCESS="%F{green}"; C_SELECTED="%B%F{white}%K{blue}"
C_INSTRUCT="%F{magenta}"
TL="┌"; TR="┐"; BL="└"; BR="┘"; H="─"; V="│"
JL="├"; JR="┤"

# --- Helper Functions for Visuals ---
_strip_ansi() { echo "$1" | sed $'s/\x1b\[[0-9;]*m//g; s/%[bfkFKB]//g'; }
_print_hline() {
    local char="${1:-$H}"; local lc="$2"; local rc="$3"; local line; local len=$(( TERMINAL_WIDTH - 2 ))
    printf -v line "%${len}s" && line=${line// /$char}
    print -P "${C_BORDER}${lc}${line}${rc}${C_RESET}"
}
_print_padded_line() { # Centered
    local text="$1"; local color="${2:-$C_OPTION_TEXT}"; local vis=$(_strip_ansi "$text"); local len=${#vis}
    local pad_tot=$(( TERMINAL_WIDTH - 2 - len )); local pad_l pad_r pad_txt
    (( pad_tot < 0 )) && pad_tot=0; pad_l=$(( pad_tot / 2 )); pad_r=$(( pad_tot - pad_l ))
    printf -v pad_txt "%*s%s%*s" $pad_l "" "$text" $pad_r ""; print -P "${C_BORDER}${V}${color}${pad_txt}${C_BORDER}${V}${C_RESET}"
}
_print_padded_line_right() { # Right-aligned
    local text="$1"; local color="${2:-$C_OPTION_TEXT}"; local vis=$(_strip_ansi "$text"); local len=${#vis}
    local pad_tot=$(( TERMINAL_WIDTH - 2 - len )); local pad_l=0 pad_r=0 pad_txt
    (( pad_tot < 0 )) && pad_tot=0; pad_l=$pad_tot
    printf -v pad_txt "%*s%s" $pad_l "" "$text"; print -P "${C_BORDER}${V}${color}${pad_txt}${C_BORDER}${V}${C_RESET}"
}
_print_empty_line() { _print_padded_line ""; }

# --- Core Helper Functions ---
create_backup() { # ... (as before) ...
    local file_to_backup="$1"; if [[ ! -f "$file_to_backup" ]]; then return 1; fi
    local backup_file="${file_to_backup}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$file_to_backup" "$backup_file"
    if (($? == 0)); then print -P "  ${C_INFO}Backup: $backup_file${C_RESET}"; return 0
    else print -P "  ${C_ERROR}Backup failed for '$file_to_backup'.${C_RESET}" >&2; return 1; fi
}
cleanup_m3u() { # ... (as before) ...
    local target_file="$1"; local temp_file; local exit_code=0; if [[ ! -f "$target_file" ]]; then return 1; fi
    print -P "${C_INFO}Cleaning up '$target_file'...${C_RESET}"; temp_file=$(mktemp "${target_file}.tmp.XXXXXX")
    if [[ -z "$temp_file" ]]; then print -P "  ${C_ERROR}Cleanup tmp fail.${C_RESET}" >&2; return 1; fi
    trap 'rm -f "$temp_file"' RETURN INT TERM HUP
    awk 'NR==1 { sub(/^\xEF\xBB\xBF/, "") } { sub(/[ \t]+$/, "") } NF > 0 { print }' "$target_file" > "$temp_file"
    if (($? != 0)); then print -P "  ${C_ERROR}Cleanup awk fail.${C_RESET}" >&2; rm -f "$temp_file"; trap - RETURN INT TERM HUP; return 1; fi
    if LC_ALL=C grep -q $'\r' "$temp_file"; then print -P "  ${C_WARN}CRLF detected.${C_RESET}" >&2; fi
    local file_info=$(file -b --mime-encoding "$target_file" 2>/dev/null || echo "unknown")
    if [[ "$file_info" != "utf-8" && "$file_info" != "us-ascii" ]]; then print -P "  ${C_WARN}Encoding not UTF-8/ASCII ($file_info).${C_RESET}" >&2; fi
    if [[ -s "$temp_file" ]]; then mv "$temp_file" "$target_file"; if (($? != 0)); then print -P "  ${C_ERROR}Cleanup mv fail.${C_RESET}" >&2; exit_code=1; else print -P "  ${C_SUCCESS}Cleanup OK.${C_RESET}"; fi
    else print -P "  ${C_WARN}Cleanup empty file. Original removed.${C_RESET}" >&2; rm -f "$target_file" "$temp_file"; exit_code=1; fi
    trap - RETURN INT TERM HUP; return $exit_code
}
extract_channels() { # ... (as before, using awk -f -) ...
    local codes_string="$1"; local output_file="$2"; local codes_array; local awk_pattern; codes_array=(${(s: :)codes_string})
    awk_pattern="group-title=\"("; for i in {1..${#codes_array[@]}}; do awk_pattern+="${codes_array[i]}"; if (( i < ${#codes_array[@]} )); then awk_pattern+="|"; fi; done; awk_pattern+=")\\|[^\"]*\""
    awk -v outfile="$output_file" -v pattern="$awk_pattern" -f - "$INPUT_FILE" <<'AWK_EOF'
BEGIN { OFS=""; print "#EXTM3U" > outfile; pending_extinf = "" } /^#EXTINF/ && $0 ~ pattern { pending_extinf = $0; next }
pending_extinf != "" { if ($0 !~ /^#/) { print pending_extinf >> outfile; print $0 >> outfile } pending_extinf = "" } END { close(outfile) }
AWK_EOF
    local awk_status=$?; if (( awk_status != 0 )); then print -P "${C_ERROR}Extract awk fail ($awk_status).${C_RESET}" >&2; rm -f "$output_file"; return 1; fi
    if [[ -f "$output_file" ]] && (( $(wc -l < "$output_file") > 1 )); then print -P "${C_SUCCESS}Extracted to $output_file${C_RESET}"; return 0; else print -P "${C_WARN}Extract no channels/empty.${C_RESET}"; rm -f "$output_file"; return 1; fi
}
split_by_country() { # ... (as before, using awk -f -) ...
    print -P "${C_INFO}Scanning/splitting...${C_RESET}"
    awk -v output_dir="$OUTPUT_DIR" -f - "$INPUT_FILE" <<'AWK_EOF'
BEGIN { OFS="" } /^#EXTM3U/ { header = $0; next }
/^#EXTINF.*group-title=/ { line = $0; if (match(line, /group-title="[A-Z]{2}\|/)) { cc_start_pos = RSTART + 13; cc = substr(line, cc_start_pos, 2); if (cc ~ /^[A-Z]{2}$/) { outfile = output_dir "/" cc ".m3u"; if (!(outfile in written_header)) { print header > outfile; if (ERRNO) { print "Error header " outfile ": " ERRNO > "/dev/stderr"; exit 1 } written_header[outfile] = 1; print "Processing " outfile "..." > "/dev/stderr" } pending_extinf = line; pending_outfile = outfile; next } else { pending_extinf = ""; pending_outfile = "" } } else { pending_extinf = ""; pending_outfile = "" } }
pending_outfile != "" { if ($0 !~ /^#/) { print pending_extinf >> pending_outfile; if (ERRNO) { print "Error EXTINF " pending_outfile ": " ERRNO > "/dev/stderr"; exit 1 } print $0 >> pending_outfile; if (ERRNO) { print "Error URL " pending_outfile ": " ERRNO > "/dev/stderr"; exit 1 } } pending_extinf = ""; pending_outfile = "" }
END { for (f in written_header) { close(f) } print "Splitting complete." > "/dev/stderr" }
AWK_EOF
    return $?
}

# --- Group Editing Functions ---
extract_groups_from_file() { # FIX: Removed typeset -gA
    local target_file="$1"; GROUP_NAMES=(); GROUP_LINES=() # Clear caller's arrays
    while IFS="|" read -r line_num group_name; do GROUP_NAMES+=("$group_name"); GROUP_LINES+=("$line_num"); done < <(awk '/^#EXTINF.*group-title=/ { line=$0; if (match(line, /group-title="([^"]+)"/)) { current_group = substr(line, RSTART+13, RLENGTH-14); if (!(current_group in seen)) { seen[current_group] = NR; print NR "|" current_group } } }' "$target_file")
}
show_group_menu() { # FIX: Use right align for options
    _print_hline $H $TL $TR; _print_padded_line "Edit Groups in '$CURRENT_COUNTRY_FILE'" "$C_TITLE"; _print_hline $H $JL $JR
    if (( ${#GROUP_NAMES[@]} == 0 )); then _print_padded_line "No groups found." "$C_WARN"; else _print_padded_line "Select a group:" "$C_INFO"; _print_empty_line; local display_text; for i in {1..${#GROUP_NAMES[@]}}; do display_text=$(printf "%s (%d)" "${GROUP_NAMES[$i]}" "$i"); if [[ -n "$selected_group_index" ]] && (( i == selected_group_index )); then _print_padded_line_right "$display_text" "$C_SELECTED"; else _print_padded_line_right "$display_text" "$C_OPTION"; fi; done; fi
    _print_hline $H $JL $JR; _print_padded_line_right "P) Print/Display channels (Interactive)" "$C_OPTION"; _print_padded_line_right "R) Rename selected group" "$C_OPTION"; _print_padded_line_right "D) Delete selected group" "$C_OPTION"; _print_empty_line; _print_padded_line_right "B) Back to Main Menu" "$C_OPTION"; _print_padded_line_right "0) Exit Script" "$C_OPTION"; _print_hline $H $BL $BR
}
get_group_end_line() { # ... (as before) ...
    local file="$1"; local selected_index="$2"; local group_start_line="${GROUP_LINES[$selected_index]}"; local next_group_start_line="" file_total_lines; if (( selected_index < ${#GROUP_LINES[@]} )); then next_group_start_line="${GROUP_LINES[$selected_index + 1]}"; fi; if [[ -n "$next_group_start_line" ]]; then echo $(( next_group_start_line - 1 )); else file_total_lines=$(wc -l < "$file"); echo "$file_total_lines"; fi
}
rename_group_in_file() { # ... (as before) ...
    local file="$1"; local index="$2"; local new_name="$3"; local start_line="${GROUP_LINES[$index]}"; local end_line old_name_quoted new_name_quoted temp_file; end_line=$(get_group_end_line "$file" "$index"); old_name_quoted=$(printf '%s\n' "${GROUP_NAMES[$index]}" | sed 's:[/\.&]:\\&:g'); new_name_quoted=$(printf '%s\n' "$new_name" | sed 's:[/\.&]:\\&:g'); print -P "  ${C_INFO}Renaming '${GROUP_NAMES[$index]}' to '$new_name'...${C_RESET}"; if ! create_backup "$file"; then return 1; fi; temp_file=$(mktemp "${file}.tmp.XXXXXX"); if [[ -z "$temp_file" ]]; then print -P "  ${C_ERROR}Rename tmp fail.${C_RESET}" >&2; return 1; fi; sed "${start_line},${end_line}s/\\(group-title=\\)\"$old_name_quoted\"/\\1\"$new_name_quoted\"/" "$file" > "$temp_file"; if (($? == 0)) && [[ -s "$temp_file" ]]; then mv "$temp_file" "$file"; print -P "  ${C_SUCCESS}Rename OK.${C_RESET}"; extract_groups_from_file "$file"; else print -P "  ${C_ERROR}Rename sed/mv fail.${C_RESET}" >&2; rm -f "$temp_file"; return 1; fi
}
delete_group_in_file() { # ... (as before, requires explicit 'y'/'Y') ...
    local file="$1"; local index="$2"; local start_line="${GROUP_LINES[$index]}" end_line temp_file confirm_delete; end_line=$(get_group_end_line "$file" "$index"); print -P "  ${C_INFO}Deleting group '${GROUP_NAMES[$index]}' (Lines $start_line-$end_line)...${C_RESET}"; print -P -n "  ${C_PROMPT}Are you SURE? [y/N]: ${C_RESET}"; read confirm_delete; if [[ "$confirm_delete" != [Yy] ]]; then print -P "  ${C_WARN}Deletion cancelled.${C_RESET}"; return 1; fi; if ! create_backup "$file"; then return 1; fi; temp_file=$(mktemp "${file}.tmp.XXXXXX"); if [[ -z "$temp_file" ]]; then print -P "  ${C_ERROR}Delete tmp fail.${C_RESET}" >&2; return 1; fi; awk -v start="$start_line" -v end="$end_line" 'NR < start || NR > end { print }' "$file" > "$temp_file"; if (($? == 0)); then if [[ ! -s "$temp_file" ]] || (( $(wc -l < "$temp_file") <= 1 && $(head -n 1 "$temp_file" 2>/dev/null) == "#EXTM3U" )); then print -P "  ${C_WARN}Empty/header-only file after delete.${C_RESET}" >&2; fi; mv "$temp_file" "$file"; print -P "  ${C_SUCCESS}Group deleted.${C_RESET}"; extract_groups_from_file "$file"; else print -P "  ${C_ERROR}Delete awk/mv fail.${C_RESET}" >&2; rm -f "$temp_file"; return 1; fi
}

# --- Interactive Channel List Functions ---
_read_key() { # ... (as before) ...
    local -n key_ref=$1; local timeout=${2:-0.1}; local key_sequence rest_of_seq; IFS= read -k 1 key_sequence; if [[ "$key_sequence" == $'\e' ]]; then if ! IFS= read -k 2 -d '' -t $timeout rest_of_seq 2>/dev/null; then key_ref=$'\e'; return; fi; key_sequence+="$rest_of_seq"; fi; key_ref="$key_sequence"
}
add_to_favorites() { # ... (as before) ...
    local extinf_line="$1"; local url_line="$2"; if [[ ! -f "$FAVORITES_FILE" ]] || [[ ! -s "$FAVORITES_FILE" ]]; then echo "#EXTM3U" > "$FAVORITES_FILE"; if (($? != 0)); then print -P "  ${C_ERROR}Create Fav fail.${C_RESET}" >&2; return 1; fi; print -P "  ${C_INFO}Initialized '$FAVORITES_FILE'.${C_RESET}"; fi; if LC_ALL=C grep -q -F -x "$url_line" "$FAVORITES_FILE"; then print -P "  ${C_WARN}Already in Fav.${C_RESET}"; return 1; fi; print -r -- "$extinf_line" >> "$FAVORITES_FILE" && print -r -- "$url_line" >> "$FAVORITES_FILE"; if (($? == 0)); then print -P "  ${C_SUCCESS}Added to Fav.${C_RESET}"; return 0; else print -P "  ${C_ERROR}Append Fav fail.${C_RESET}" >&2; return 1; fi
}
delete_channel_from_group_file() { # FIX: Use print -P -n, require explicit y/Y
    local file="$1"; local group_start_line="$2"; local channel_index_in_group="$3"; local line1_to_delete=$(( group_start_line + (channel_index_in_group - 1) * 2 )); local line2_to_delete=$(( line1_to_delete + 1 )); local confirm_del temp_file sed_status; print -P "  ${C_WARN}Will delete lines $line1_to_delete & $line2_to_delete.${C_RESET}"; print -P -n "  ${C_PROMPT}Confirm delete channel? [y/N]: ${C_RESET}"; read confirm_del; if [[ "$confirm_del" != [Yy] ]]; then print -P "  ${C_WARN}Deletion cancelled.${C_RESET}"; return 1; fi; if ! create_backup "$file"; then return 1; fi; temp_file=$(mktemp "${file}.tmp.XXXXXX"); if [[ -z "$temp_file" ]]; then print -P "  ${C_ERROR}Delete chan tmp fail.${C_RESET}" >&2; return 1; fi; sed -e "${line1_to_delete}d" -e "${line2_to_delete}d" "$file" > "$temp_file"; sed_status=$?; if (( sed_status == 0 )) && [[ -s "$temp_file" ]]; then mv "$temp_file" "$file"; if (($? == 0)); then print -P "  ${C_SUCCESS}Chan deleted from '$file'.${C_RESET}"; return 0; else print -P "  ${C_ERROR}Delete chan mv fail.${C_RESET}" >&2; rm -f "$temp_file"; return 1; fi; else print -P "  ${C_ERROR}Delete chan sed fail ($sed_status) or empty.${C_RESET}" >&2; rm -f "$temp_file"; return 1; fi
}
interactive_channel_list() { # ... (as before) ...
    local file="$1"; local group_start_line="$2"; local group_end_line="$3"; local group_name="$4"; local -a channel_extinfs channel_urls; local current_index=1 top_index=1 total_channels window_height; local key_pressed needs_redraw=1 status_message=""; while IFS='|' read -r type line_content; do if [[ "$type" == "E" ]]; then channel_extinfs+=("$line_content"); elif [[ "$type" == "U" ]]; then channel_urls+=("$line_content"); fi; done < <(awk -v start="$group_start_line" -v end="$group_end_line" 'NR >= start && NR <= end { if (/^#EXTINF/) { print "E|" $0 } else if ($0 !~ /^#/) { print "U|" $0 } }' "$file"); total_channels=${#channel_extinfs[@]}; if (( total_channels == 0 )); then print -P "${C_WARN}No channels found.${C_RESET}"; sleep 1; return; fi; window_height=$(( TERMINAL_HEIGHT - 5 )); (( window_height < 3 )) && window_height=3; tput civis; trap 'tput cnorm; exit 1' INT TERM HUP; trap 'tput cnorm' RETURN
    while true; do if (( needs_redraw )); then tput clear; tput cup 0 0; _print_hline $H $TL $TR; _print_padded_line "Group: ${group_name} (${total_channels} channels)" "$C_TITLE"; _print_padded_line "UP/DOWN | RIGHT=Fav | LEFT=Del | Q/B/ESC=Back" "$C_INSTRUCT"; _print_hline $H $JL $JR; local end_visible_index=$(( top_index + window_height - 1 )); (( end_visible_index > total_channels )) && end_visible_index=$total_channels; for (( i=top_index; i<=end_visible_index; i++ )); do local extinf_display="${channel_extinfs[$i]}"; local url_display="${channel_urls[$i]}"; local max_len=$(( TERMINAL_WIDTH - 6 )); (( ${#extinf_display} > max_len )) && extinf_display="${extinf_display:0:$((max_len-3))}..."; (( ${#url_display} > max_len )) && url_display="${url_display:0:$((max_len-3))}..."; local line1_prefix line2_prefix line_color text_color; if (( i == current_index )); then line1_prefix=">${C_SELECTED} $(printf "%3d" $i)${C_RESET}${C_SELECTED}"; line2_prefix=" ${C_SELECTED}    ${C_RESET}${C_SELECTED}"; line_color="$C_SELECTED"; text_color="$C_SELECTED"; else line1_prefix="  $(printf "%3d" $i) "; line2_prefix="      "; line_color="$C_OPTION_TEXT"; text_color="$C_OPTION_TEXT"; fi; local visible_line1=$(_strip_ansi "${line1_prefix} ${extinf_display}"); local pad1=$(( TERMINAL_WIDTH - 2 - ${#visible_line1} )); (( pad1 < 0 )) && pad1=0; printf -v pad1_spaces "%${pad1}s"; print -P "${C_BORDER}${V}${line_color}${line1_prefix} ${text_color}${extinf_display}${pad1_spaces}${C_BORDER}${V}${C_RESET}"; local visible_line2=$(_strip_ansi "${line2_prefix} ${url_display}"); local pad2=$(( TERMINAL_WIDTH - 2 - ${#visible_line2} )); (( pad2 < 0 )) && pad2=0; printf -v pad2_spaces "%${pad2}s"; print -P "${C_BORDER}${V}${line_color}${line2_prefix} ${text_color}${url_display}${pad2_spaces}${C_BORDER}${V}${C_RESET}"; done; local lines_drawn=$(( (end_visible_index - top_index + 1) * 2 )); local lines_to_fill=$(( window_height * 2 - lines_drawn )); for ((k=1; k<=lines_to_fill; k++)); do _print_empty_line; done; _print_hline $H $JL $JR; local visible_status=$(_strip_ansi "$status_message"); local status_len=${#visible_status}; local status_pad_total=$(( TERMINAL_WIDTH - 2 - status_len )); local status_pad_left status_pad_right status_padded; if (( status_pad_total < 0 )); then status_pad_total=0; fi; status_pad_left=$(( status_pad_total / 2 )); status_pad_right=$(( status_pad_total - status_pad_left )); printf -v status_padded "%*s%s%*s" $status_pad_left "" "$status_message" $status_pad_right ""; print -P "${C_BORDER}${V}${C_INFO}${status_padded}${C_BORDER}${V}${C_RESET}"; _print_hline $H $BL $BR; needs_redraw=0; status_message=""; fi
        tput cup $((TERMINAL_HEIGHT - 1)) 0; print -P -n "${C_PROMPT}Action Ch.$current_index: ${C_RESET}"; tput el; _read_key key_pressed; local exit_interactive=0; case "$key_pressed" in ($'\e[A') if (( current_index > 1 )); then (( current_index-- )); if (( current_index < top_index )); then (( top_index-- )); fi; needs_redraw=1; else status_message="Already at top"; needs_redraw=1; fi;; ($'\e[B') if (( current_index < total_channels )); then (( current_index++ )); if (( current_index >= (top_index + window_height) )); then (( top_index++ )); fi; needs_redraw=1; else status_message="Already at bottom"; needs_redraw=1; fi;; ($'\e[C') local fav_output fav_status; fav_output=$(add_to_favorites "${channel_extinfs[$current_index]}" "${channel_urls[$current_index]}" 2>&1); fav_status=$?; status_message="Fav: $fav_output"; needs_redraw=1;; ($'\e[D') local delete_output del_status; delete_output=$(delete_channel_from_group_file "$file" "$group_start_line" "$current_index" 2>&1); del_status=$?; status_message="Del: $delete_output"; if (( del_status == 0 )); then exit_interactive=1; else needs_redraw=1; fi;; ('q'|'Q'|'b'|'B'|$'\e') exit_interactive=1;; (*) status_message="Unknown key."; needs_redraw=1;; esac; (( exit_interactive )) && break; done; tput cnorm; tput clear; return 0
}
edit_country_groups() { # FIX: Use print -P for prompts
    local country_code CURRENT_COUNTRY_FILE selected_group_index=""; local -a GROUP_NAMES GROUP_LINES
    print -P -n "${C_PROMPT}Enter 2-letter country code to edit: ${C_RESET}"; read country_code; country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]' | cut -c1-2); CURRENT_COUNTRY_FILE="${OUTPUT_DIR}/${country_code}.m3u"; if [[ ! -f "$CURRENT_COUNTRY_FILE" ]]; then print -P "${C_ERROR}File '$CURRENT_COUNTRY_FILE' not found.${C_RESET}" >&2; sleep 1; return; fi; extract_groups_from_file "$CURRENT_COUNTRY_FILE"; if (( ${#GROUP_NAMES[@]} == 0 )); then print -P "${C_WARN}No groups found in '$CURRENT_COUNTRY_FILE'.${C_RESET}"; sleep 1; return; fi
    while true; do clear; show_group_menu; if [[ -n "$selected_group_index" ]]; then print -P "Selected: ${C_SELECTED}${selected_group_index}) ${GROUP_NAMES[$selected_group_index]}${C_RESET}"; else print -P "${C_INFO}Select group number, then action (P/R/D).${C_RESET}"; fi; print -P -n "${C_PROMPT}Enter selection or action: ${C_RESET}"; read sub_choice; if [[ "$sub_choice" =~ ^[0-9]+$ ]] && (( sub_choice >= 1 && sub_choice <= ${#GROUP_NAMES[@]} )); then selected_group_index=$sub_choice; continue; elif [[ "$sub_choice" == "0" ]]; then print -P "${C_INFO}Exiting script.${C_RESET}"; tput cnorm; exit 0; fi; action=$(echo "$sub_choice" | tr '[:lower:]' '[:upper:]'); case "$action" in (P) if [[ -z "$selected_group_index" ]]; then print -P "${C_ERROR}Select group first.${C_RESET}"; sleep 1; continue; fi; local start_ln="${GROUP_LINES[$selected_group_index]}"; local end_ln=$(get_group_end_line "$CURRENT_COUNTRY_FILE" "$selected_group_index"); interactive_channel_list "$CURRENT_COUNTRY_FILE" "$start_ln" "$end_ln" "${GROUP_NAMES[$selected_group_index]}"; extract_groups_from_file "$CURRENT_COUNTRY_FILE"; selected_group_index=""; ;; (R) if [[ -z "$selected_group_index" ]]; then print -P "${C_ERROR}Select group first.${C_RESET}"; sleep 1; continue; fi; print -P -n "${C_PROMPT}New name for '${GROUP_NAMES[$selected_group_index]}': ${C_RESET}"; read new_group_name; if [[ -n "$new_group_name" ]]; then rename_group_in_file "$CURRENT_COUNTRY_FILE" "$selected_group_index" "$new_group_name"; selected_group_index=""; else print -P "${C_WARN}Rename cancelled.${C_RESET}"; fi; sleep 1;; (D) if [[ -z "$selected_group_index" ]]; then print -P "${C_ERROR}Select group first.${C_RESET}"; sleep 1; continue; fi; print -P "${C_ERROR}WARN: Delete group '${GROUP_NAMES[$selected_group_index]}' AND channels!${C_RESET}"; print -P -n "${C_PROMPT}Are you SURE? [y/N]: ${C_RESET}"; read confirm_delete; if [[ "$confirm_delete" == [yY] ]]; then delete_group_in_file "$CURRENT_COUNTRY_FILE" "$selected_group_index"; selected_group_index=""; else print -P "${C_WARN}Deletion cancelled.${C_RESET}"; fi; sleep 1;; (B) print -P "${C_INFO}Returning to main menu...${C_RESET}"; return ;; (*) if ! [[ "$sub_choice" =~ ^[0-9]+$ ]]; then print -P "${C_ERROR}Invalid input.${C_RESET}"; else print -P "${C_ERROR}Invalid group number.${C_RESET}"; fi; sleep 1;; esac; done
}
show_main_menu() { # FIX: Use right align for options
    _print_hline $H $TL $TR; _print_padded_line "M3U Management Menu" "$C_TITLE"; _print_hline $H $JL $JR
    _print_padded_line_right "1) Split by Country (Create ${OUTPUT_DIR}/[CC].m3u)" "$C_OPTION"
    _print_padded_line_right "2) Create Custom Playlist (${OUTPUT_DIR}/...)" "$C_OPTION"
    _print_padded_line_right "3) Edit Groups in a Country File" "$C_OPTION"; _print_empty_line
    _print_padded_line_right "0) Exit" "$C_OPTION"; _print_hline $H $BL $BR
}

# --- Main Script Logic ---
if ! command -v tput >/dev/null 2>&1; then echo "Error: 'tput' missing." >&2; fi
if ! command -v file >/dev/null 2>&1; then echo "Warning: 'file' missing." >&2; fi
if [[ ! -f "$INPUT_FILE" ]]; then print -P "${C_ERROR}Input '$INPUT_FILE' not found.${C_RESET}"; exit 1; fi
mkdir -p "$OUTPUT_DIR"; if [[ ! -d "$OUTPUT_DIR" ]]; then print -P "${C_ERROR}Cannot create dir '$OUTPUT_DIR'.${C_RESET}"; exit 1; fi
print -P "${C_INFO}Input: ${C_RESET}${INPUT_FILE}"; print -P "${C_INFO}Output: ${C_RESET}${OUTPUT_DIR}"; print -P "${C_INFO}Favorites: ${C_RESET}${FAVORITES_FILE}"

while true; do clear; show_main_menu; print -P -n "${C_PROMPT}Enter your choice: ${C_RESET}"; read choice
  case "$choice" in
    1) print -P "${C_INFO}Will create/overwrite files in '$OUTPUT_DIR'.${C_RESET}"; print -P -n "${C_PROMPT}Proceed? [Y/n]: ${C_RESET}"; read confirm_split; if [[ "$confirm_split" == [Nn] ]]; then print -P "${C_WARN}Cancelled.${C_RESET}"; else split_by_country; if (($? == 0)); then print -P "\n${C_INFO}Splitting OK. Cleaning files...${C_RESET}"; find "$OUTPUT_DIR" -maxdepth 1 -name '*.m3u' -print0 | while IFS= read -r -d $'\0' file; do [[ -f "$file" ]] && cleanup_m3u "$file"; done; print -P "${C_SUCCESS}Cleanup OK.${C_RESET}"; else print -P "${C_ERROR}Split fail.${C_RESET}" >&2; fi; fi; print -P -n "\n${C_INFO}Press Enter...${C_RESET}"; read dummy;;
    2) print -P -n "${C_PROMPT}Codes (e.g., IT UK):${C_RESET} "; read codes_in; codes_s=$(echo "$codes_in"|tr '[:lower:]' '[:upper:]'|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'); if [[ -z "$codes_s" ]]; then print -P "${C_WARN}No codes.${C_RESET}"; sleep 1; continue; fi; out_base=$(echo "$codes_s"|sed 's/ /-/g'); out_f="${OUTPUT_DIR}/${out_base}.m3u"; print -P "${C_INFO}Output: $out_f${C_RESET}"; if [[ -f "$out_f" ]]; then print -P -n "${C_PROMPT}Exists. Overwrite? [Y/n]: ${C_RESET}"; read ovr_ch; if [[ "$ovr_ch" == [Nn] ]]; then print -P "${C_WARN}Cancelled.${C_RESET}"; sleep 1; continue; fi; rm -f "$out_f"; fi; extract_channels "$codes_s" "$out_f"; if (($? == 0)); then cleanup_m3u "$out_f"; else rm -f "$out_f"; fi; print -P -n "\n${C_INFO}Press Enter...${C_RESET}"; read dummy;;
    3) edit_country_groups ;;
    0) print -P "${C_INFO}Exiting.${C_RESET}"; tput cnorm; break ;;
    *) print -P "${C_ERROR}Invalid choice.${C_RESET}"; sleep 1 ;;
  esac
done
tput cnorm; print -P "\n${C_SUCCESS}Done.${C_RESET}"
print -P "${C_INFO}Validate files in '$OUTPUT_DIR'.${C_RESET}"; exit 0