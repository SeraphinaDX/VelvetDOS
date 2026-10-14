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
        cls.img = (BIN / "velvetdos-0.1.0.img").read_bytes()
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
        self.assertIn(b"VelvetDOS 0.1.0", kernel)

    def test_both_fats_identical(self):
        self.assertEqual(self.fat[:3], b"\xf0\xff\xff")
        self.assertEqual(self.fat, self.img[74*512:83*512])

    def test_program_contents_match_cluster_chains(self):
        files = {name: (BIN / name).read_bytes() for name in ("HELLO.COM", "RETURN.COM", "CHAIN.COM")}
        for i, (name, original) in enumerate(files.items()):
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
            self.assertTrue(original.startswith(b"\xba"), "expected native 16-bit MOV DX,imm16")

    def test_multicluster_com(self):
        size = (BIN / "CHAIN.COM").stat().st_size
        self.assertGreater(size, 1024)
        cluster = struct.unpack_from("<H", self.root, 2 * 32 + 26)[0]
        self.assertEqual(cluster, 4)
        self.assertEqual(fat_next(self.fat, cluster), 5)
        self.assertEqual(fat_next(self.fat, 5), 6)
        self.assertEqual(fat_next(self.fat, 6), 0xfff)

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
