enhance the Nipe Control plugin with the following improvements:
Visual & UX Improvements:

- Added loading spinners with animation in the bar widget
- Tooltips on bar widget showing detailed status (IP, country, error)
- Color-coded status banner with border when active
- Visual leak test results with color coding (green=OK, red=leak, yellow=testing)
- Better error/warning cards with icons
  add New Features:
- Country detection - Shows exit node country code/name in bar and popout (uses ipinfo.io by default)
- Leak test - One-click DNS/IP leak verification in popout
- Status change notifications - Desktop alerts when Nipe starts/stops
- Auto-start on boot setting (requires sudoers setup)
  Enhanced Settings:
- Show/hide country code toggle
- Enable/disable notifications
- Auto-start on login
- Customizable IP info API endpoint
- Helpful tips section in settings
  Helper Script Updates:
- New leak-test command that checks for DNS leaks and verifies exit IP
- Better dependency checking
- Updated usage documentation
  Files Modified:
- NipeControl.qml - Complete UI overhaul with new features
- NipeControlSettings.qml - Enhanced settings with all new options
- nipe-widget.sh - Added leak test functionality
- plugin.json - Updated capabilities, permissions, version 2.0.0
- README.md - Comprehensive documentation update
- adnan0-im-nipecontrol.json - Updated metadata
  The plugin now requires curl, jq, and libnotify-bin (or libnotify) as additional dependencies for the new features.
