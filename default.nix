{ nixpkgs ?
    # Default for CI reproducibility, optionally override in your configuration.nix.
    (import ((import <nixpkgs> {}).pkgs.fetchFromGitHub {
      owner = "NixOS"; repo = "nixpkgs";
      rev = "b61238243c978cde19a0676f3da9e3fd575e55fc";
      sha256 = "0s8s68ax8xvn99gq5xjs78fbs88azjbmqdwqjvizkjl9bjzl8sxx";
    }) {
      # We need updated Hackage hashes to be able to use `callHackage`
      # below. Remove this after switching to a sufficient version of
      # Nixpkgs.
      config.packageOverrides = super: let self = super.pkgs; in {
        all-cabal-hashes = self.fetchFromGitHub {
          owner = "commercialhaskell";
          repo = "all-cabal-hashes";
          rev = "5a1b0706a7b8f53517408c20a260789a70b8fe54";
          sha256 = "0x30j503ygfin7zdgggv79ghm3sjnj15fdgigic8rg5rjpvnk1rz";
        };
      };
    })
, compiler ? "ghc802" # TODO: try using "default"?
, haskellPackages ? if compiler == "default"
                      then nixpkgs.pkgs.haskellPackages
                      else nixpkgs.pkgs.haskell.packages.${compiler}
}:

with nixpkgs.pkgs.haskell.lib;

let

  inherit (nixpkgs) pkgs;

  appendGIFlags = p: appendConfigureFlag p "-f-overloaded-methods -f-overloaded-signals -f-overloaded-properties";

  fixCairoGI = p: overrideCabal p (drv: {
    preCompileBuildDriver = (drv.preCompileBuildDriver or "") + ''
      export LD_LIBRARY_PATH="${pkgs.cairo}/lib"
    '';
  });

  extendedHaskellPackages = haskellPackages.override {
    overrides = self: super:
      let
        jsaddlePkgs = import ./vendor/jsaddle   self; # FIXME: unused?   # TODO: if not, use `fetchFromGitHub`?
        ghcjsDom    = import ./vendor/ghcjs-dom self; # TODO: use `fetchFromGitHub`?
      in {
        jsaddle = jsaddlePkgs.jsaddle;
        jsaddle-warp = dontCheck jsaddlePkgs.jsaddle-warp;
        jsaddle-wkwebview = overrideCabal jsaddlePkgs.jsaddle-wkwebview;
        jsaddle-webkit2gtk = jsaddlePkgs.jsaddle-webkit2gtk;
        jsaddle-dom = overrideCabal (self.callPackage ./jsaddle-dom {}) (drv: {
          # On macOS, the jsaddle-dom build will run out of file handles the first time it runs
          preBuild = ''./setup build || true'';
        });
        ghcjs-dom-jsaddle = dontHaddock ghcjsDom.ghcjs-dom-jsaddle;
        ghcjs-dom-jsffi = ghcjsDom.ghcjs-dom-jsffi;
        ghcjs-dom = dontCheck (dontHaddock ghcjsDom.ghcjs-dom);

        gi-atk = appendGIFlags super.gi-atk;
        gi-cairo = appendGIFlags (fixCairoGI super.gi-cairo);
        gi-gdk = appendGIFlags (fixCairoGI super.gi-gdk);
        gi-gdkpixbuf = appendGIFlags super.gi-gdkpixbuf;
        gi-gio = appendGIFlags super.gi-gio;
        gi-glib = appendGIFlags super.gi-glib;
        gi-gobject = appendGIFlags super.gi-gobject;
        gi-gtk = appendGIFlags (fixCairoGI super.gi-gtk);
        gi-javascriptcore = appendGIFlags super.gi-javascriptcore_4_0_11;
        gi-pango = appendGIFlags (fixCairoGI super.gi-pango);
        gi-soup = appendGIFlags super.gi-soup;
        gi-webkit2 = appendGIFlags (fixCairoGI super.gi-webkit2);
        gi-gtksource = appendGIFlags (fixCairoGI super.gi-gtksource);
        gi-gtkosxapplication = appendGIFlags (fixCairoGI (super.gi-gtkosxapplication.override {
          gtk-mac-integration-gtk3 = pkgs.gtk-mac-integration-gtk3;
        }));
        haskell-gi = super.haskell-gi;
        haskell-gi-base = super.haskell-gi-base;
        webkit2gtk3-javascriptcore = overrideCabal super.webkit2gtk3-javascriptcore (drv: {
          preConfigure = ''
            mkdir dispatch
            sed 's|^\(typedef void [(]\)\^\(dispatch_block_t[)][(]void[)];\)$|\1\2|' <"${pkgs.stdenv.cc.libc}/include/dispatch/object.h" >dispatch/object.h
            '';
        });

        haskell-gi-overloading = dontHaddock (self.callHackage "haskell-gi-overloading" "0.0" {});

        # FIXME: do we really need them as Git submodules?
        vcswrapper = self.callCabal2nix "vcswrapper" ./vendor/haskellVCSWrapper/vcswrapper {};
        vcsgui = self.callCabal2nix "vcsgui" ./vendor/haskellVCSGUI/vcsgui {};
        ltk = overrideCabal (self.callCabal2nix "ltk" ./vendor/ltk {}) (drv: {
          libraryPkgconfigDepends = with pkgs; [ gnome3.gtk.dev ] ++ (if stdenv.isDarwin then [ gtk-mac-integration-gtk3 ] else []);
        });
        leksah-server = dontCheck (self.callCabal2nix "leksah-server" ./vendor/leksah-server {}); # FIXME: really `dontCheck`?

        # TODO: optionally add:
        # • yi >=0.12.4 && <0.13,
        # • yi-language >=0.2.0 && <0.3,
        # • yi-rope >=0.7.0.1 && <0.8
      };
  };

  cleanSrc =
    builtins.filterSource (path: type: # FIXME: How to re-use .gitignore? https://git.io/vSo80
      nixpkgs.lib.all (i: toString i != path) [ ./.git ./dist-newstyle ./cabal.project.local ] # TODO: what else?
      ) ./.;

  # TODO: try to autogenerate this blob using `callCabal2Nix` (+ `overrideCabal` for Darwin tweaks)
  drv =
    { mkDerivation, array, base, base-compat, binary
    , binary-shared, blaze-html, bytestring, Cabal, conduit, containers
    , cpphs, deepseq, directory, executable-path, filepath, fsnotify, ghc
    , ghcjs-codemirror, gi-cairo, gi-gdk, gi-gdkpixbuf, gi-gio, gi-glib
    , gi-gobject, gi-gtk, gi-gtk-hs, gi-gtkosxapplication, gi-gtksource
    , gi-pango, gi-webkit2, haskell-gi, haskell-gi-base, haskell-src-exts
    , hlint, hslogger, HTTP, mtl, network
    , network-uri, old-time, parsec, pretty, pretty-show, QuickCheck
    , regex-base, regex-tdfa, regex-tdfa-text, shakespeare, split
    , stdenv, stm, strict, text, time, transformers, unix, utf8-string
    , vado, vcsgui, vcswrapper, call-stack, HUnit, doctest, hspec, gnome3
    , pkgconfig, darwin, buildPackages, gtk-mac-integration-gtk3
    , happy, alex

    , haskell-gi-overloading, ltk, leksah-server
    }:
    mkDerivation {
      pname = "leksah";
      version = "0.16.2.2";
      src = cleanSrc;
      isLibrary = true;
      isExecutable = true;
      libraryHaskellDepends = [
        array base base-compat binary binary-shared blaze-html bytestring
        Cabal conduit containers cpphs deepseq directory executable-path
        filepath fsnotify ghc ghcjs-codemirror gi-cairo gi-gdk gi-gdkpixbuf gi-gio
        gi-glib gi-gobject gi-gtk gi-gtk-hs
        gi-gtksource gi-pango gi-webkit2 haskell-gi haskell-gi-base haskell-src-exts
        hlint hslogger HTTP mtl network network-uri
        old-time parsec pretty pretty-show QuickCheck regex-base regex-tdfa
        regex-tdfa-text shakespeare split stm strict text time transformers
        unix utf8-string vado call-stack HUnit doctest
        hspec gnome3.defaultIconTheme pkgconfig gnome3.gtk gnome3.gtksourceview gnome3.webkitgtk

        haskell-gi-overloading vcswrapper vcsgui ltk leksah-server
      ] ++ (if stdenv.isDarwin then [
        gi-gtkosxapplication
        gtk-mac-integration-gtk3
        darwin.libobjc
        buildPackages.darwin.apple_sdk.frameworks.Cocoa
        buildPackages.darwin.apple_sdk.libs.xpc
        (buildPackages.osx_sdk or null)
      ] else []);
      buildDepends = [ nixpkgs.cabal-install happy alex gnome3.dconf ];
      libraryPkgconfigDepends = [ gnome3.gtk.dev gnome3.gtksourceview gnome3.webkitgtk nixpkgs.cairo gnome3.gsettings_desktop_schemas ]
        ++ (if stdenv.isDarwin then [ gtk-mac-integration-gtk3 ] else []);
      executableHaskellDepends = [ base ];
      homepage = "http://www.leksah.org";
      description = "Haskell IDE written in Haskell";
      license = "GPL";
    };

  build = pkgs.stdenv.lib.overrideDerivation (overrideCabal (extendedHaskellPackages.callPackage drv {}) (oldAttrs: {

    # TODO: add Darwin tweaks here.

  })) (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ (with pkgs; [ wrapGAppsHook makeWrapper ]);
    postFixup = ''
      wrapProgram $out/bin/leksah \
        --prefix 'PATH' ':' "${extendedHaskellPackages.leksah-server}/bin"
    '';
  });

  env = pkgs.stdenv.lib.overrideDerivation build.env (oldAttrs: {
    # TODO: perhaps add some additional stuff to nix-shell PATH?
    shellHook = ''
      export CFLAGS="$NIX_CFLAGS_COMPILE" # TODO: why is this needed?
      export XDG_DATA_DIRS="$GSETTINGS_SCHEMAS_PATH:$XDG_DATA_DIRS" # TODO: how to do this better?
      export PATH="${extendedHaskellPackages.leksah-server}/bin:$PATH"
    '';
  });

in build // { inherit env; }
