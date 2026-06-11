// Handler for the custom "mdedit:" URL protocol.
// The viewer's "✎ 편집" button links to  mdedit:<percent-encoded abs path> .
// Windows hands this exe the whole string as argv[0]; we strip the scheme,
// URL-decode the path, and open it in an external editor.
//
// Editor: first non-comment line of editor.txt (next to this exe) if present,
// otherwise notepad.exe.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class MdEdit
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 0) return 1;

        string arg = args[0];
        int colon = arg.IndexOf(':');
        string enc = (colon >= 0) ? arg.Substring(colon + 1) : arg;
        enc = enc.TrimStart('/');                 // tolerate mdedit:///path
        string path;
        try { path = Uri.UnescapeDataString(enc); }
        catch { path = enc; }
        if (string.IsNullOrWhiteSpace(path)) return 1;

        string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string editor = "notepad.exe";
        try
        {
            string cfg = Path.Combine(exeDir, "editor.txt");
            if (File.Exists(cfg))
            {
                foreach (string line in File.ReadAllLines(cfg))
                {
                    string t = line.Trim();
                    if (t.Length > 0 && !t.StartsWith("#")) { editor = t; break; }
                }
            }
        }
        catch { }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = editor,
                Arguments = "\"" + path + "\"",
                UseShellExecute = true,
            });
        }
        catch
        {
            try { Process.Start("notepad.exe", "\"" + path + "\""); }
            catch { return 1; }
        }
        return 0;
    }
}
