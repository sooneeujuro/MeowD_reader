// Tiny windowless launcher for the Markdown viewer.
// Explorer can register this .exe as an "Open with" handler for .md.
// It simply runs:  <pythonw>  <its-own-folder>\md_view.py  "<the .md file>"
// so md_view.py stays editable without recompiling this shim.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

internal static class MdViewLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string exeDir = Path.GetDirectoryName(
            Assembly.GetExecutingAssembly().Location);
        string script = Path.Combine(exeDir, "md_view.py");

        // Prefer the windowless launchers so no console window flashes.
        string[] candidates =
        {
            @"C:\Windows\pyw.exe",   // py launcher (windowless), standard python.org install
            "pythonw.exe",            // resolved via PATH
            "pyw.exe",
        };

        string launcher = null;
        foreach (string c in candidates)
        {
            if (c.IndexOf('\\') >= 0)
            {
                if (File.Exists(c)) { launcher = c; break; }
            }
            else
            {
                launcher = c; // resolved via PATH by CreateProcess
                break;
            }
        }
        if (launcher == null) { launcher = "pythonw.exe"; }

        var sb = new StringBuilder();
        sb.Append('"').Append(script).Append('"');
        foreach (string a in args)
        {
            sb.Append(" \"").Append(a).Append('"');
        }

        var psi = new ProcessStartInfo
        {
            FileName = launcher,
            Arguments = sb.ToString(),
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = exeDir,
        };

        try
        {
            Process.Start(psi);
        }
        catch (Exception)
        {
            return 1;
        }
        return 0;
    }
}
