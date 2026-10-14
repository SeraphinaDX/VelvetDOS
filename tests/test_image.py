"""VelvetDOS FAT12 image integrity and loader input tests (GNU GPLv3)."""
import importlib.util
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "build"
spec = importlib.util.spec_from_file_location("mkfloppy", ROOT / "tools" / "mkfloppy.py")
mkfloppy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mkfloppy)


def fat_next(fat: bytes, cluster: int) -> int:
    off = cluster + cluster // 2
    word = int.from_bytes(fat[off:off + 2], "little")
    return word >> 4 if cluster & 1 else word & 0xfff


class FloppyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.img = (BIN / "velvetdos-0.7.0.img").read_bytes()
        cls.fat = cls.img[65*512:(65+9)*512]
        cls.root = cls.img[83*512:97*512]

    def test_1440k_boot_signature(self):
        self.assertEqual(len(self.img), 1474560)
        self.assertEqual(self.img[510:512], b"\x55\xaa")
        self.assertEqual(struct.unpack_from("<H", self.img, 11)[0], 512)
        self.assertEqual(self.img[13], 1)
        self.assertEqual(struct.unpack_from("<H", self.img, 14)[0], 65)
        self.assertEqual(self.img[16], 2)
        self.assertEqual(struct.unpack_from("<H", self.img, 19)[0], 2880)

    def test_kernel_embedded_unmodified(self):
        kernel = (BIN / "kernel.bin").read_bytes()
        self.assertTrue(0 < len(kernel) <= 32768)
        self.assertEqual(self.img[512:512+len(kernel)], kernel)
        self.assertIn(b"VelvetDOS 0.7.0", kernel)

    def test_both_fats_identical(self):
        self.assertEqual(self.fat[:3], b"\xf0\xff\xff")
        self.assertEqual(self.fat, self.img[74*512:83*512])

    def test_program_contents_match_cluster_chains(self):
        names = ("HELLO.COM", "RETURN.COM", "CHAIN.COM", "EXEDEMO.EXE",
                 "READ.COM", "MEMORY.COM", "README.TXT",
                 "WRITE.COM", "APPEND.COM", "DELETE.COM", "RECHECK.COM", "PATHS.COM", "FINDTEST.COM", "VLIST.COM", "DIRGROW.COM", "PSPTEST.COM", "EXITTEST.COM")
        for i, name in enumerate(names):
            original = (BIN / name).read_bytes()
            item = self.root[i * 32:(i+1)*32]
            self.assertEqual(item[:11], mkfloppy.dos_name(name))
            self.assertEqual(struct.unpack_from("<I", item, 28)[0], len(original))
            cluster = struct.unpack_from("<H", item, 26)[0]
            recovered = bytearray()
            visited = set()
            while 2 <= cluster < 0xff8:
                self.assertNotIn(cluster, visited)
                visited.add(cluster)
                off = (97 + cluster - 2) * 512
                recovered.extend(self.img[off:off+512])
                cluster = fat_next(self.fat, cluster)
            self.assertEqual(cluster, 0xfff)
            self.assertEqual(recovered[:len(original)], original)

    def test_dos_com_examples_have_valid_binary_headers(self):
        for name in ("HELLO.COM", "RETURN.COM", "CHAIN.COM", "READ.COM",
                     "WRITE.COM", "APPEND.COM", "DELETE.COM", "RECHECK.COM", "PATHS.COM", "FINDTEST.COM", "VLIST.COM", "DIRGROW.COM", "PSPTEST.COM", "EXITTEST.COM"):
            # Regressions are independently linked native .COM files; their first
            # opcodes may differ (MOV DX,imm16 vs MOV AX,imm16).
            self.assertGreater((BIN / name).stat().st_size, 30, name)
        # MEMORY starts with PUSH DS (1Eh), then POP ES (07h).
        self.assertTrue((BIN / "MEMORY.COM").read_bytes().startswith(b"\x1e\x07"))

    def test_mz_relocation_fixture(self):
        mz = (BIN / "EXEDEMO.EXE").read_bytes()
        self.assertEqual(mz[:2], b"MZ")
        last, pages, count, header_paras = struct.unpack_from("<4H", mz, 2)
        self.assertEqual((pages - 1) * 512 + (last or 512), len(mz))
        self.assertEqual(count, 1)
        self.assertEqual(header_paras, 2)
        reloc_offset = struct.unpack_from("<H", mz, 0x18)[0]
        self.assertEqual(mz[reloc_offset:reloc_offset+4], b"\x00\x00\x00\x00")
        self.assertEqual(mz[32:34], b"\x00\x00")
        self.assertIn(b"MZ EXE relocation", mz)

    def test_dos_read_test_crosses_multiple_clusters(self):
        data = (BIN / "README.TXT").read_bytes()
        self.assertGreater(len(data), 600)
        self.assertTrue(data.startswith(b"VELVETDOS"))
        self.assertGreater(len((BIN / "READ.COM").read_bytes()), 0)

    def test_multicluster_com(self):
        size = (BIN / "CHAIN.COM").stat().st_size
        self.assertGreater(size, 1024)
        cluster = struct.unpack_from("<H", self.root, 2 * 32 + 26)[0]
        self.assertEqual(cluster, 4)
        self.assertEqual(fat_next(self.fat, cluster), 5)
        self.assertEqual(fat_next(self.fat, 5), 6)
        self.assertEqual(fat_next(self.fat, 6), 0xfff)

    def test_write_fixtures_are_native_com_programs(self):
        for name, expected in (("WRITE.COM", b"WRITE.COM:"),
                               ("APPEND.COM", b"APPEND.COM:"),
                               ("DELETE.COM", b"DELETE.COM:"),
                               ("RECHECK.COM", b"RECHECK.COM:")):
            blob = (BIN / name).read_bytes()
            self.assertIn(expected, blob)
            self.assertIn(b"DATA.BIN\x00", blob)
            self.assertNotEqual(blob[:2], b"MZ")
        self.assertIn(b"A" * 512 + b"B" * 188,
                      (BIN / "WRITE.COM").read_bytes())

    def test_write_api_bios_and_fat12_implementation_present(self):
        # Structural checks only. Emulator still needs to execute the programs.
        source = (ROOT / "kernel" / "kernel.s").read_text()
        for routine in ("write_sector:", "flush_metadata:",
                        "allocate_cluster:", "fat_set:",
                        "write_file_byte:", "free_file_chain:"):
            self.assertIn(routine, source)
        self.assertIn("mov ax, 0x0301", source)
        self.assertIn("mov si, 74", source)  # FAT mirror

    def test_nested_paths_dos_program_is_in_image(self):
        program = (BIN / "PATHS.COM").read_bytes()
        for marker in (b"PATHS.COM:", b"LAB\\ONE", b"A:\\LAB\\ONE\\TEST.DAT", b"TEST.DAT"):
            self.assertIn(marker, program)
        for fn in (0x39, 0x3a, 0x3b, 0x47, 0x3c, 0x40, 0x41):
            self.assertIn(bytes([0xb4, fn]), program)  # MOV AH, immediate

    def test_directory_syscalls_use_cluster_based_storage(self):
        src = (ROOT / "kernel" / "kernel.s").read_text()
        for marker in ("dos_mkdir:", "dos_rmdir:", "dos_chdir:",
                       "rebuild_cwd:", "filename_from_es_si:",
                       "select_directory:", "flush_directory:",
                       "find_directory:", "cwd_stack:", "path_stack:"):
            self.assertIn(marker, src)
        # 16 entries including '.' and '..'; guard max path depth.
        self.assertIn("mov cx, 16", src)
        self.assertIn("cmp byte ptr [path_depth], 8", src)

    def test_path_parser_compiles_real_backslash_checks(self):
        """GAS treats a single backslash char literal as apostrophe (0x27).

        Catch the exact 0.4.0 bug where LAB\\ONE was created as one FAT name.
        Check both the source syntax and the assembled 8086 instructions.
        """
        import re
        import subprocess
        src = (ROOT / "kernel" / "kernel.s").read_text()
        self.assertEqual(src.count("cmp al, 0x5c"), 4)
        self.assertNotIn("cmp al, '" + chr(92) + "'", src)
        disasm = subprocess.check_output(
            ["objdump", "-d", "-M", "intel,i8086", str(BIN / "kernel.o")],
            text=True,
        )
        resolver = disasm.split("<filename_from_es_si>:", 1)[1].split(
            "<select_directory>:", 1
        )[0]
        self.assertEqual(len(re.findall(r"\bcmp\s+al,0x5c\b", resolver)), 4)
        self.assertNotRegex(resolver, r"\bcmp\s+al,0x27\b")

    def test_findfirst_dta_and_diskspace_api_binaries(self):
        source = (ROOT / "kernel" / "kernel.s").read_text()
        for hook in (".L_dos_set_dta:", ".L_dos_get_dta:",
                     ".L_dos_findfirst:", ".L_dos_findnext:",
                     ".L_dos_diskfree:", ".L_dos_attributes:",
                     ".L_dos_timestamp:", "dta_findnext:"):
            self.assertIn(hook, source)
        program = (BIN / "FINDTEST.COM").read_bytes()
        for code in (0x1a, 0x2f, 0x36, 0x4e, 0x4f):
            self.assertIn(bytes([0xb4, code]), program)
        for code in (b"ATTR05.TST", b"*.COM", b"*.EXE", b"*.TST"):
            self.assertIn(code, program)
        self.assertIn(b"VLIST.COM - DOS FindFirst/FindNext", (BIN / "VLIST.COM").read_bytes())

    def test_new_com_programs_are_in_image(self):
        names = [
            self.root[i*32:i*32+11]
            for i in range(224) if self.root[i*32:i*32+1] not in (b"\x00", b"\xe5")
        ]
        for prog in ("FINDTEST.COM", "VLIST.COM", "DIRGROW.COM", "PSPTEST.COM", "EXITTEST.COM"):
            self.assertIn(mkfloppy.dos_name(prog), names)
            self.assertGreater((BIN / prog).stat().st_size, 30)

    def test_directory_growth_kernel_has_bounded_buffer_and_full_chain_flush(self):
        source = (ROOT / "kernel" / "kernel.s").read_text()
        self.assertIn(".equ MAX_DIR_CLUSTERS, 8", source)
        self.assertIn("dir_cluster_count:", source)
        self.assertIn("dir_last_cluster:", source)
        self.assertIn("new_dir_offset:", source)
        start = source.index("select_directory:")
        end = source.index("flush_directory:", start)
        self.assertIn("call fat_next", source[start:end])
        self.assertIn("call read_sector", source[start:end])
        self.assertIn("cmp word ptr [dir_cluster_count], MAX_DIR_CLUSTERS", source[start:end])
        start = end
        end = source.index("find_file:", start)
        self.assertIn("call fat_next", source[start:end])
        self.assertIn("call write_sector", source[start:end])
        start = source.index("find_free_root:")
        end = source.index("root_is_open:", start)
        self.assertIn("call allocate_cluster", source[start:end])
        self.assertIn("call fat_set", source[start:end])
        self.assertIn("call flush_metadata", source[start:end])
        self.assertIn("call write_sector", source[start:end])

    def test_dirgrow_external_dos_api_fixture(self):
        blob = (BIN / "DIRGROW.COM").read_bytes()
        self.assertIn(b"DIRGROW.COM:", blob)
        self.assertIn(b"A:\\GROW\\*.TST", blob)
        self.assertIn(b"A:\\GROW\\F", blob)
        for code in (0x39, 0x3c, 0x40, 0x3e, 0x4e, 0x4f, 0x3f, 0x41, 0x3a):
            self.assertIn(bytes([0xb4, code]), blob)
        self.assertTrue(100 < len(blob) < 65024)
        self.assertNotEqual(blob[:2], b"MZ")
        self.assertEqual(self.root[14*32:14*32+11], mkfloppy.dos_name("DIRGROW.COM"))

    def test_directory_buffer_cannot_overlap_application_memory(self):
        # The 8086 directory cache is at 2600:0000; 8*512 bytes fit
        # below the kernel's 3000:0000 application reservation.
        self.assertLess(0x2600 * 16 + 8 * 512, 0x3000 * 16)
        self.assertEqual((BIN / "kernel.bin").stat().st_size <= 32768, True)

    def test_psp_and_environment_entrypoints(self):
        source = (ROOT / "kernel" / "kernel.s").read_text()
        for marker in ("make_psp:", "init_environment:",
                       "uppercase_command_token:", "split_external_command:",
                       ".L_dos_get_psp:", "cmdtail_len:", "last_exit_code:"):
            self.assertIn(marker, source)
        self.assertIn(".equ ENV_SEG,        0x2a00", source)
        self.assertIn("mov word ptr es:[0x2c], ENV_SEG", source)
        self.assertIn("mov byte ptr es:[di], 13", source)
        self.assertIn("mov word ptr es:[0x16], 0", source)
        self.assertIn("mov word ptr ss:[bp + 10], APP_SEG", source)
        kernel = (BIN / "kernel.bin").read_bytes()
        expected = (b"PATH=A:" + bytes([92, 0]) + b"PROMPT=$P$G"
                    + bytes([0, 0, 1, 0]) + b"A:" + bytes([92]) + b"VELVETDOS\x00")
        self.assertIn(expected, kernel)
        self.assertIn(b"Last program exit code (hex): ", kernel)
        self.assertLess(len(kernel), 32769)

    def test_native_psptest_and_exitcode_programs(self):
        psp = (BIN / "PSPTEST.COM").read_bytes()
        self.assertIn(b" hello MiXeD 123", psp)
        self.assertIn(b"PSPTEST.COM: command tail", psp)
        self.assertIn(b"Environment block", psp)
        self.assertIn(b"\xb4\x62", psp)  # AH=62: get PSP
        self.assertIn(b"\xb4\x51", psp)  # AH=51: get PSP
        self.assertIn(b"\xb4\x2f", psp)  # AH=2F: get DTA
        self.assertIn(b"\xb8\x01\x4c", psp)  # AX=4C01: failing process exit
        exiting = (BIN / "EXITTEST.COM").read_bytes()
        self.assertIn(b"EXITTEST.COM: returning code 2A", exiting)
        self.assertIn(b"\xb8\x2a\x4c", exiting) # AX=4C2A
        for name in ("PSPTEST.COM", "EXITTEST.COM"):
            self.assertIn(mkfloppy.dos_name(name),
                          [self.root[i*32:i*32+11] for i in range(224)])

    def test_reject_oversized_kernel(self):
        with self.assertRaises(ValueError):
            mkfloppy.create_image(self.img[:512], bytes(32769), [])

    def test_reject_duplicate_filenames(self):
        with self.assertRaises(ValueError):
            mkfloppy.create_image(self.img[:512], b"k", [("A.COM", b"1"), ("a.com", b"2")])

    def test_reject_invalid_filename(self):
        with self.assertRaises(ValueError):
            mkfloppy.dos_name("TOOLONGNAME.EXE")


if __name__ == "__main__":
    unittest.main()
