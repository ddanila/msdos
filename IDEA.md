The idea of this repo is to make repeatable build of MS-DOS 4.0 released by MS using modern OS like Linux as a host.
Pipeline should look like this:
1. kvikdos to run required compilers and linkers natively under Linux to build the images.
2. deploy result images to the headless QEMU and have some test startup script that will output "OK" to the COM1.
3. check the output of QEMU -- so we will have the ability to identify if deployment succeeded and MSDOS booted up.

That's MVP

Future to think of:
1. More tests ran after deployment.
2. Some logging feedback on what is happening on the screen.