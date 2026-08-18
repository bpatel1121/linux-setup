# todoman — tasks as iCalendar VTODOs, stored in the SAME vdir khal reads.
# One storage layer for events and todos; both sync together through
# vdirsyncer whenever that gets wired up.
#
#   todo new "grade problem sets" --due "fri 17:00"
#   todo list            # open tasks
#   todo done 3          # check one off
#
# The bar chip (scripts/waybar-todos.sh) counts tasks due within 24h and
# turns red when anything is overdue. SUPER+SHIFT+A opens the list.

path = "~/.local/share/khal/calendars/*"
default_list = "personal"

# date/time formats must match what waybar-todos.sh parses
date_format = "%Y-%m-%d"
time_format = "%H:%M"

# a bare `todo new "x"` gets no artificial due date
default_due = 0
