(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2021 OCamlPro SAS                                       *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Lesser General    *)
(*  Public License version 2.1, with the special exception on linking     *)
(*  described in the LICENSE.md file in the root directory.               *)
(*                                                                        *)
(*                                                                        *)
(**************************************************************************)

open Ezcmd.V2
open EzFile.OP
open EZCMD.TYPES
open Types

let hardcoded_code_hashes = [
  "a491804ca55dd5b28cffdff48cb34142930999621a54acee6be83c342051d884",
  "SetcodeMultisigWallet24" ;
  "7d0996943406f7d62a4ff291b1228bf06ebd3e048b58436c5b70fb77ff8b4bf2",
  "SafeMultisigWallet24" ;
  "5daea8b855140d110ab07d430883bfecdd4cba9bcded8968fae7fa6cdb5adfbd",
  "FreeTonContest" ;


]

let bin_install file =
  let basename = Filename.basename file in
  Misc.call [ "cp" ; "-f" ; file ; Globals.bin_dir // basename ]

let install_tonos_cli config ~distclean =
  Unix.chdir Globals.git_dir ;
  let dir = Globals.git_dir // "tonos-cli" in
  if distclean then Misc.call [ "rm"; "-rf"; dir ];

  let exists = Sys.file_exists dir in
  if not exists then
    Misc.call [ "git" ; "clone"; ( Config.repos config ).repo_tonos_cli ;
                "tonos-cli" ];
  Unix.chdir dir;
  if exists then begin
    Misc.call [ "git" ; "pull" ];
    Misc.call [ "cargo" ; "update" ];
  end;
  Misc.call [ "cargo"; "build" ];
  bin_install "target/debug/tonos-cli" ;
  Misc.call [ "cargo"; "clean" ];
  ()

let install_solc config ~distclean =
  Unix.chdir Globals.git_dir ;
  let dir = Globals.git_dir // "TON-Solidity-Compiler" in
  if distclean then Misc.call [ "rm"; "-rf"; dir ];
  let exists = Sys.file_exists dir in
  if not exists then
    Misc.call [ "git" ; "clone";
                ( Config.repos config ).repo_solc ;  "TON-Solidity-Compiler" ];
  Unix.chdir dir;
  if exists then
    Misc.call [ "git" ; "pull" ];
  Printf.eprintf "If deps are missing, use:\n";
  Printf.eprintf "  cd %s\n" dir;
  Printf.eprintf "  sh ./compiler/scripts/install_deps.sh\n%!";
  (* Misc.call [ "sh" ; "./compiler/scripts/install_deps.sh" ]; *)
  EzFile.make_dir ~p:true "build";
  Unix.chdir "build";
  Misc.call [ "cmake" ; "../compiler/" ; "-DCMAKE_BUILD_TYPE=Release" ];
  Misc.call [ "cmake" ; "--build" ; "." ; "--" ; "-j8" ];
  Unix.chdir "..";

  bin_install "build/solc/solc" ;
  bin_install "lib/stdlib_sol.tvm" ;
  ()

let install_tvm_linker config ~distclean =
  Unix.chdir Globals.git_dir ;
  let dir = Globals.git_dir // "TVM-linker" in
  if distclean then Misc.call [ "rm"; "-rf"; dir ];

  let exists = Sys.file_exists dir in
  if not exists then
    Misc.call [ "git" ; "clone";
                ( Config.repos config) .repo_tvm_linker ;  "TVM-linker" ];
  Unix.chdir dir;
  if exists then
    Misc.call [ "git" ; "pull" ];
  Unix.chdir "tvm_linker";
  if exists then
    Misc.call [ "cargo" ; "update" ];
  Misc.call [ "cargo"; "build" ];
  bin_install "target/debug/tvm_linker" ;
  Misc.call [ "Cargo"; "clean" ];
  ()

let install_code_hashes () =
  List.iter (fun file ->
      if Filename.dirname file = "contracts" then
        match EzString.split (Filename.basename file) '.' with
        | [ name ; "tvc" ] ->
            Printf.eprintf "Getting TVC code Hash of %s\n%!" name;
            ignore ( Misc.get_contract_file ".tvc" name )
        | _ -> ()
    ) Files.file_list;
  List.iter (fun ( code_hash, contract ) ->
      Misc.register_code_hash ~code_hash ~contract
    ) hardcoded_code_hashes;

  ()

let action ~distclean ~client ~solc ~linker ~code_hashes =
  let config = Config.config () in

  if code_hashes then install_code_hashes ();

  if Globals.is_alpine then begin
    Printf.eprintf
      "Docker detected. Use 'docker pull ocamlpro/ft:latest' to upgrade\n%!";
  end else begin
    EzFile.make_dir ~p:true Globals.git_dir ;
    EzFile.make_dir ~p:true Globals.bin_dir ;

    if distclean && not (client || solc || linker ) then
      Misc.call [ "rm"; "-rf"; Globals.git_dir ];

    if client then
      install_tonos_cli config ~distclean ;
    if solc then install_solc config ~distclean ;
    if linker then install_tvm_linker config ~distclean ;
  end;
  ()

let cmd =
  let distclean = ref false in
  let client = ref false in
  let solc = ref false in
  let linker = ref false in
  let code_hashes = ref false in

  EZCMD.sub
    "init"
    (fun () ->
       let client, solc, linker, code_hashes =
         match !client, !solc, !linker, !code_hashes with
         | false, false, false, false -> true, true, true, true
         | client, solc, linker, code_hashes ->
             client, solc, linker, code_hashes
       in
       action ~distclean:!distclean ~client ~solc ~linker ~code_hashes
    )
    ~args: [
      [ "distclean" ], Arg.Set distclean,
      EZCMD.info "Clean completely before building";

      [ "client" ], Arg.Set client,
      EZCMD.info "Build and install 'tonos-cli' from sources";
      [ "solc" ], Arg.Set solc,
      EZCMD.info "Build and install 'solc' from sources";
      [ "linker" ], Arg.Set linker,
      EZCMD.info "Build and install 'tvm_linker' from sources";
      [ "code-hashes" ], Arg.Set code_hashes,
      EZCMD.info "Create a database of code hashes from predefined contracts";
    ]
    ~doc: "Initialize with TON Labs binary tools, compiled from sources."
    ~man:[
      `S "DESCRIPTION";
      `Blocks [
        `P "Initialize with TON Labs binary tools, downloading them \
            from their GIT repositories and compiling them (a recent \
            Rust compiler must be installed).";
        `P "Tools are installed in $HOME/.ft/bin/.";
        `P "The following tools can be installed:";
        `I ("1.", "The 'tonos-cli' client");
        `I ("2.", "The 'solc' client from the TON-Solidity-Compiler repository");
        `I ("3.", "The 'tvm_linker' encoder from the TVM-linker repository");
        `P "If no specific option is specified, all tools are \
            generated. If a tool has already been generated, calling \
            it again will try to upgrade to a more recent version."
      ];
    ]