# Carga el puente de MediaRemote (biblioteca de Dynamic Notch) dentro de /usr/bin/perl, que está firmado por Apple
# y por eso puede leer "lo que está sonando" en macOS 15.4 y posteriores. Uso: perl MediaRemoteBridge.pl <dylib>
use strict;
use DynaLoader;
my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die "No se pudo cargar el puente: " . DynaLoader::dl_error() . "\n";
my $entry = DynaLoader::dl_find_symbol($lib, "dn_media_bridge_main") or die "Puente sin punto de entrada\n";
DynaLoader::dl_install_xsub("main::run_bridge", $entry);
run_bridge();
