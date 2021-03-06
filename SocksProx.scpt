JsOsaDAS1.001.00bplist00�Vscript_�/*
 * SocksProx
 *
 * A simple applet to initiate a SOCKS5 VPN tunnel via SSH
 *
 * 1) Ensure you have an SSH key set up with your server
 * 2) Use a browser plugin (eg: FoxyProxy) to map to localhost:8080
 *
 * By Daniel Demby (https://github.com/heliomass)
 */

var SocksProxApplet = function() {

	'use strict';
	
	// Default tunnel period in seconds (default to 3 hours).
	var tunnelPeriod = 10800;

	// Reference to the current application.
	var app = Application.currentApplication();
	app.includeStandardAdditions = true;
	
	/*
	 * runShell
	 *
	 * Executes a shell command.
	 *
	 * Inputs:
	 *    cmd - String containing the shell command to be executed.
	 *
	 * Returns an array double:
	 *    Item 1: true (return code 0), false otherwise
	 *    Item 2: The output or error depending on the outcome of the command
	 */
	var runShell = function(cmd) {

		try {
			var output = app.doShellScript(cmd);
			return new Array (true, output);
		} catch (e) {
			return new Array (false, e);
		}
	
	}

	/*
	 * confirm
	 *
	 * A confirmation prompt.
	 *
	 * Inputs:
	 *    text       - The text to display
	 *    buttonName - The text for the confirmation button
	 *    timeout    - An optional timeout
	 */
	var confirm = function(text, buttonName, timeout) {

		if (timeout !== undefined) {
	  		return app.displayDialog(text, {buttons: [buttonName || 'OK'], givingUpAfter: timeout});
		} else {
			return app.displayDialog(text, {buttons: [buttonName || 'OK']});
		}
	
	}

	/*
	 * getTunnelPeriod
	 *
	 * Crude function to take an integer in seconds, and
	 * return a string with the approximate amount of time
	 * the tunnel will remain open.
	 *
	 * Inputs:
	 *    tunnelPeriod - Period in seconds
	 */
	var getTunnelPeriodText = function(tunnelPeriod) {

		if (tunnelPeriod < 60) {
			tunnelPeriodText = String(tunnelPeriod + ' seconds');
		} else if (tunnelPeriod === 60) {
			tunnelPeriodText = '1 minute';
		} else if (tunnelPeriod < 3600) {
			tunnelPeriodText = String((tunnelPeriod / 60) + ' minutes');
		} else if (tunnelPeriod === 3600) {
			tunnelPeriodText = '1 hour';
		} else {
			tunnelPeriodText = String((tunnelPeriod / 60 / 60) + ' hours');
		}
	
		return tunnelPeriodText;

	}

	/*
	 * prompt
	 *
	 * Prompts for text input, with optional default value.
	 *
	 * Inputs:
	 *    text          - String containing prompt text
	 *    defaultAnswer - Optional string containing pre-populated text for the field
	 *
	 * Returns:
	 *    User input, or null on error.
	 */
	var prompt = function(text, defaultAnswer) {
		var options = { defaultAnswer: defaultAnswer || '' }
		try {
			return app.displayDialog(text, options).textReturned;
		} catch (e) {
			return null;
		}
	}


	/*
	 * getServer
	 *
	 * Prompts user for ssh server name
	 */
	var getServer = function(defaultAnswer) {
		return prompt('Choose your SSH server:', defaultAnswer);
	}

	/*
	 * getUser
	 *
	 * Prompts user for ssh username
	 */
	var getUser = function(defaultAnswer) {
		return prompt('Username:', defaultAnswer);
	}
	
	var showCountDown = function(timeout, pid) {
	
		var timeoutUnits = timeout * 10;
		
		Progress.description = `Tunnel active (pid ${pid})`;
		Progress.additionalDescription = `Preparing...`;
		Progress.totalUnitCount = timeoutUnits;
		
		try {
			for (var i = 0; i < timeoutUnits; i++) {
				if ((timeoutUnits - i) >= 35400) {
					var timeDisplay = Math.ceil((timeoutUnits - i) / 36000).toString();
					var timeUnit = 'hours';
				} else if ((timeoutUnits - i) <= 590) {
					var timeDisplay = Math.ceil((timeoutUnits - i) / 10).toString();
					var timeUnit = 'seconds';
				} else {
					var timeDisplay = Math.ceil((timeoutUnits - i) / 600).toString();
					var timeUnit = 'minutes';
				}
				Progress.additionalDescription = `Tunnel will remain open for ${timeDisplay} ${timeUnit}`;
				delay(0.1);
				Progress.completedUnitCount = i;
			}
		} catch (e) {
			return false;
		}
		
		return true;
	
	}

	/*
	 * Properties
	 *
	 * Creates an object which can read and write settings from a file
	 * in the user's home directory.
	 *
	 * Used to prepopulate the servername and username on subsequent runs.
	 *
	 * Adapted from: https://gist.github.com/RobTrew/6bc1fcc997844faec3cf
	 */
	var Properties = function (app, dctDefaults) {
	
		// read any json in a file that shares the path 
		// (except .json extension) of this script
		var strPath = app.pathTo("home folder") + '/.vpn_props'
		var json = $.NSString.stringWithContentsOfFile(strPath).js || "";

		return {
			// fill any gaps (using dctDefaults) in the json settings
			keys: function (dctA, dctB) {
				for (var key in dctB) {
					if (!(key in dctA)) dctA[key] = dctB[key];
				}
				return dctA;
			}(json && JSON.parse(json) || {}, dctDefaults),

			// update the json, probably best used at end of script
			write: function () {
				$.NSString.alloc.initWithUTF8String(
					JSON.stringify(this.keys)
				).writeToFileAtomically(strPath, true);
			}
		};
	};
	
	// Get textual representation of tunnel period for user display.
	var tunnelPeriodText = getTunnelPeriodText(tunnelPeriod);

	// Read in the settings file
	var props = new Properties(app, {server: '', username: ''})

	// Prompt user for server and username
	var server = getServer(props.keys['server']);
	var username = getUser(props.keys['username']);
	
	// Ensure the user has filled out the servername and username
	if (!server || server === '' || !username || username === '') {
		throw('Please supply a server and username.');
	}

	// Write the updated settings back to the prefs file.
	props.keys['server'] = server;
	props.keys['username'] = username;
	props.write();

	// Initiate the tunnel! The return value is the PID of the ssh command.
	var tunnel = runShell(`ssh -o PasswordAuthentication=no -D 8080 ${username}@${server} sleep ${tunnelPeriod} > /dev/null 2>&1 & echo $!`);

	// Check the ssh command was successful.
	if (tunnel[0] !== true) {
		throw(tunnel[1]);
	}
	
	// Now we wait a brief moment, to see if the ssh tunnel survives.
	delay(0.25);
	
	// Check the process ID for the tunnel to see if it's still alive
	var checkTunnel = runShell('ps -f ' + tunnel[1]);
	if (checkTunnel[0] !== true) {
		throw('Unable to start tunnel: ' + checkTunnel[1]);
	}

	// Display a dalogue box to the user. When they dismiss this dialogue, the tunnel will terminate.
	// It also closes automatically after 3 hours, to match the tunnel alive time.
	var result = showCountDown(tunnelPeriod, tunnel[1]);

	// Check whether the dialogue timed out by itself. If so, let the user know the tunnel expired.
	if (result === false) {
		var killPID = runShell('kill ' + tunnel[1]);
		if (killPID[0] !== true) {
			confirm('Tunnel may have already been terminated: ' + killPID[1], 'OK', 30);
		}
	} else {
		confirm('Tunnel timed out.', 'OK', 30);
	}

}();
                              � jscr  ��ޭ