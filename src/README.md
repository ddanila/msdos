# MS-DOS v1.25, v2.0, and v4.0 source fork

This is the `ddanila/MS-DOS` development fork of Microsoft's historical MS-DOS
source release. It retains the original MS-DOS v1.25 and v2.0 sources and
binaries and the jointly developed IBM/Microsoft MS-DOS 4.0 sources.

The fork's `main` branch contains maintained MS-DOS 4.0 source fixes, build
compatibility changes, command help, and runtime-test improvements used by the
[`ddanila/msdos`](https://github.com/ddanila/msdos) native build environment.
That repository pins an exact commit from this fork and provides the custom
JWasm/Open Watcom toolchain, deployment process, and automated kvikdos/QEMU
tests.

The translated files under `.readmes/` are archived translations of the
original Microsoft repository description. They document the origin of the
source release, not this fork's current development policy.

## Source integrity

The historical sources contain significant filename-case, line-ending, and
character-encoding requirements. Preserve the repository's `.gitattributes`
policy and byte content when editing them. In particular, some assembly files
contain CP437 bytes and some message/build-control files require CRLF on disk.

## License and provenance

Microsoft originally published the MS-DOS v1.25 and v2.0 files through the
[Computer History Museum](https://computerhistory.org/blog/microsoft-ms-dos-early-source-code/)
and later published them together with the MS-DOS 4.0 source on GitHub.

All files in this repository are released under the MIT License as described by
[LICENSE](LICENSE). Preserve copyright and attribution notices in modified
source files.

Microsoft names and logos remain subject to Microsoft's trademark guidelines.
Modified versions must not imply Microsoft sponsorship or endorsement.
