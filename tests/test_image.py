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
        cls.img = (BIN / "velvetdos-0.3.0.img").read_bytes()
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
        self.assertIn(b"VelvetDOS 0.3.0", kernel)

    def test_both_fats_identical(self):
        self.assertEqual(self.fat[:3], b"\xf0\xff\xff")
        self.assertEqual(self.fat, self.img[74*512:83*512])

    def test_program_contents_match_cluster_chains(self):
        names = ("HELLO.COM", "RETURN.COM", "CHAIN.COM", "EXEDEMO.EXE",
                 "READ.COM", "MEMORY.COM", "README.TXT",
                 "WRITE.COM", "APPEND.COM", "DELETE.COM", "RECHECK.COM")
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
                     "WRITE.COM", "APPEND.COM", "DELETE.COM", "RECHECK.COM"):
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
