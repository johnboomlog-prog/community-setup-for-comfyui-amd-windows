using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows.Forms;

internal static class Program
{
    private const string ReleaseVersion = "__RELEASE_VERSION__";
    private const string ResourceName = "community_setup_payload.zip";

    [STAThread]
    private static void Main()
    {
        try
        {
            string root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CommunitySetupForComfyUI",
                ReleaseVersion);
            string marker = Path.Combine(root, ".payload-ready");

            if (!File.Exists(marker))
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(root, true);
                }

                Directory.CreateDirectory(root);
                using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
                {
                    if (payload == null)
                    {
                        throw new InvalidOperationException("The embedded deployment files are missing.");
                    }

                    using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            string destination = Path.GetFullPath(Path.Combine(root, entry.FullName));
                            string expectedRoot = Path.GetFullPath(root + Path.DirectorySeparatorChar);
                            if (!destination.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase))
                            {
                                throw new InvalidDataException("The embedded package contains an unsafe path.");
                            }

                            if (String.IsNullOrEmpty(entry.Name))
                            {
                                Directory.CreateDirectory(destination);
                                continue;
                            }

                            Directory.CreateDirectory(Path.GetDirectoryName(destination));
                            using (Stream input = entry.Open())
                            using (FileStream output = File.Create(destination))
                            {
                                input.CopyTo(output);
                            }
                        }
                    }
                }

                File.WriteAllText(marker, ReleaseVersion);
            }

            string wizard = Path.Combine(root, "launcher", "Community-Setup-for-ComfyUI.ps1");
            if (!File.Exists(wizard))
            {
                throw new FileNotFoundException("The deployment wizard could not be extracted.", wizard);
            }

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \"" + wizard + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(wizard)
            };
            Process.Start(start);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "部署向导无法启动。\n\nThe deployment wizard could not start.\n\n" + ex.Message,
                "Community Setup for ComfyUI",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
