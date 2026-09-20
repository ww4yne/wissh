import Foundation

enum SSHTmuxControlCommandBuilder {
    static let tmuxNotFoundMarker = "remux: tmux executable not found"
    static let tmuxNotExecutableMarker = "remux: tmux executable cannot be executed"

    private static let fallbackRemotePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func attachOrCreateControlSessionCommand(
        multiplexer: TerminalMultiplexer = .tmux,
        tmuxExecutable: String,
        sessionName: String,
        initialViewport: TmuxControlViewport
    ) -> String {
        if multiplexer == .psmux {
            return powerShellCommand(
                script: psmuxLaunchScript(
                    executable: tmuxExecutable,
                    sessionName: sessionName,
                    initialViewport: initialViewport
                )
            )
        }

        // The SSH login shell only parses this wrapper. /bin/sh owns the PATH
        // expression so fish and csh do not need to understand POSIX syntax.
        return [
            "exec /bin/sh -c '\(launchScript)' remux",
            octalEncodedArgument(tmuxExecutable),
            octalEncodedArgument(sessionName),
            "\(initialViewport.columns)",
            "\(initialViewport.rows)",
        ].joined(separator: " ")
    }

    static func listSessionsCommand(
        multiplexer: TerminalMultiplexer = .tmux,
        tmuxExecutable: String
    ) -> String {
        if multiplexer == .psmux {
            return powerShellCommand(
                script: psmuxDiscoveryScript(executable: tmuxExecutable)
            )
        }

        // Discovery runs through an ordinary SSH exec channel, never the
        // control-mode channel. Keep the configured executable out of the
        // login shell just as the attach command does.
        return [
            "exec /bin/sh -c '\(discoveryScript)' remux",
            octalEncodedArgument(tmuxExecutable),
        ].joined(separator: " ")
    }

    private static let launchScript = [
        #"PATH="${PATH:+$PATH:}\#(fallbackRemotePath)""#,
        "export PATH",
        "TERM=xterm-256color",
        "export TERM",
        #"tmux=$(printf %b "$1")"#,
        #"session=$(printf %b "$2")"#,
        #"resolved=$(command -v "$tmux" 2> /dev/null)"#,
        #"if [ -x "$resolved" ]; then exec "$resolved" -u -C new-session -A -s "$session" -x "$3" -y "$4"; fi"#,
        #"if [ -e "$tmux" ]; then echo "\#(tmuxNotExecutableMarker): $tmux" >&2; exit 126; fi"#,
        #"echo "\#(tmuxNotFoundMarker): $tmux" >&2"#,
        "exit 127",
    ].joined(separator: "; ")

    private static let discoveryScript = [
        #"PATH="${PATH:+$PATH:}\#(fallbackRemotePath)""#,
        "export PATH",
        "LC_ALL=C",
        "export LC_ALL",
        #"tmux=$(printf %b "$1")"#,
        #"resolved=$(command -v "$tmux" 2> /dev/null)"#,
        "if [ -x \"$resolved\" ]; then exec \"$resolved\" list-sessions -F \"#{session_name}\"; fi",
        #"if [ -e "$tmux" ]; then echo "\#(tmuxNotExecutableMarker): $tmux" >&2; exit 126; fi"#,
        #"echo "\#(tmuxNotFoundMarker): $tmux" >&2"#,
        "exit 127",
    ].joined(separator: "; ")

    private static func octalEncodedArgument(_ value: String) -> String {
        let bytes = value.utf8.map { byte in
            let digits = String(byte, radix: 8)
            return "\\0" + String(repeating: "0", count: 3 - digits.count) + digits
        }
        return "'\(bytes.joined())'"
    }

    private static func psmuxLaunchScript(
        executable: String,
        sessionName: String,
        initialViewport: TmuxControlViewport
    ) -> String {
        """
        $ErrorActionPreference='Stop';\
        $exe=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(base64(executable))'));\
        $session=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(base64(sessionName))'));\
        $resolved=(Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source);\
        if(-not $resolved){[Console]::Error.WriteLine('\(tmuxNotFoundMarker): '+$exe);exit 127};\
        try{& $resolved new-session -A -d -s $session -x \(initialViewport.columns) -y \(initialViewport.rows);\
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};\
        & $resolved resize-window -x \(initialViewport.columns) -y \(initialViewport.rows) -t $session;\
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};\
        $env:PSMUX_SESSION_NAME=$session;\
        & $resolved -CC;\
        exit $LASTEXITCODE}\
        catch{[Console]::Error.WriteLine('\(tmuxNotExecutableMarker): '+$exe);exit 126}
        """
    }

    private static func psmuxDiscoveryScript(executable: String) -> String {
        """
        $ErrorActionPreference='Stop';\
        $exe=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(base64(executable))'));\
        $resolved=(Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source);\
        if(-not $resolved){[Console]::Error.WriteLine('\(tmuxNotFoundMarker): '+$exe);exit 127};\
        try{& $resolved list-sessions -F '#{session_name}';exit $LASTEXITCODE}\
        catch{[Console]::Error.WriteLine('\(tmuxNotExecutableMarker): '+$exe);exit 126}
        """
    }

    private static func powerShellCommand(script: String) -> String {
        guard let data = script.data(using: .utf16LittleEndian) else {
            preconditionFailure("PowerShell scripts must be encodable as UTF-16LE")
        }
        let encoded = data.base64EncodedString()
        return "powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand \(encoded)"
    }

    private static func base64(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }
}
