# Compatibility references

The retail English baselines are:

- [MS-DOS 5.0 User's Guide and Reference (1991)](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_5/Microsoft_-_MS-DOS_5.0_Users_Guide_and_Reference_1991.pdf)
- [MS-DOS Programmer's Reference (1991)](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_5/Microsoft_-_MS-DOS_Programmers_Reference_1991.pdf)
- [MS-DOS 6.22 User's Guide (1994)](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_6.22/DOS_6.22_Users_Manual_1994.pdf)
- [Archived DOS 6.22 Help](https://www.infania.net/misc/dos622help/)
- [Supplemental Disk inventory, KB Q117600](https://ftp.zx.net.nz/pub/archive/ftp.microsoft.com/MISC/KB/en-us/117/600.HTM)

Keep downloaded manuals in git-ignored `.reference/`; they are not redistributed.
For searchable text, install Ghostscript, save the DOS 5 manual as
`.reference/msdos5/users-guide.pdf`, then run:

```sh
gs -q -dNOPAUSE -dBATCH -sDEVICE=txtwrite \
  -sOutputFile=.reference/msdos5/users-guide.txt \
  .reference/msdos5/users-guide.pdf
```

Use `.reference/msdos622/users-guide.{pdf,txt}` for the DOS 6.22 manual.
Genuine DOS and Windows media are external test inputs, not repository fixtures.

An optional `MS-DOS/` checkout is an ignored reference copy of
[`ddanila/MS-DOS`](https://github.com/ddanila/MS-DOS), not a submodule or build
input. Maintained source belongs in `src/`. Generated root-level `floppy.img`
files are also ignored; use `make deploy` to reproduce `out/floppy.img`.
