# Local compatibility references

Copyrighted product manuals are kept in the git-ignored `.reference/`
directory and are not redistributed by this repository.

The DOS 5 compatibility baseline is the 1991 Microsoft *MS-DOS 5.0 User's
Guide and Reference*. Download it from the URL recorded in `DOS5_GAPS.md`, then
extract searchable text with Ghostscript:

```sh
mkdir -p .reference/msdos5
gs -q -dNOPAUSE -dBATCH -sDEVICE=txtwrite \
  -sOutputFile=.reference/msdos5/users-guide.txt \
  .reference/msdos5/users-guide.pdf
```
