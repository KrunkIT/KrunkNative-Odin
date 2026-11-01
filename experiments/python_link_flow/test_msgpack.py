import unittest
from unittest.mock import patch

from krunker_msgpack import AhNum, HosterAhNum, decode_packets, decode_trailer, encode_packets, pack, unpack_one
from link_flow import initial_player_messages


class MessagePackTests(unittest.TestCase):
    def test_round_trip_values(self) -> None:
        value = ["en", [0, 2482, [-1, -1], None, True], {"0-4": -1}, "hé"]
        encoded = pack(value)
        decoded, consumed = unpack_one(encoded)
        self.assertEqual(decoded, value)
        self.assertEqual(consumed, len(encoded))

    def test_concatenated_packets_and_trailer(self) -> None:
        wire = encode_packets([["load"], ["po"]], 0xDA)
        ah_num, messages = decode_packets(wire)
        self.assertEqual(ah_num, 0xDA)
        self.assertEqual(messages, [["load"], ["po"]])
        self.assertEqual(wire[-2:], bytes((0x0D, 0x0A)))

    def test_trailer_is_two_nibbles(self) -> None:
        self.assertEqual(decode_trailer(bytes((0x0F, 0x0F))), 0xFF)

    def test_all_counter_values_round_trip(self) -> None:
        for ah_num in range(256):
            wire = encode_packets([["po"]], ah_num)
            decoded_ah, messages = decode_packets(wire)
            self.assertEqual(decoded_ah, ah_num)
            self.assertEqual(messages, [["po"]])

    def test_live_counter_step_and_wrap(self) -> None:
        counter = AhNum()
        observed = [counter.for_opcode("po") for _ in range(86)]
        self.assertEqual(observed[:7], [37, 74, 111, 148, 185, 222, 3])
        self.assertEqual(observed[-1], 110)

    def test_live_counter_matches_reference_hoster(self) -> None:
        counter, hoster = AhNum(), HosterAhNum()
        for index in range(600):
            message = ["q" if index % 2 else "v"]
            self.assertEqual(counter.encode(message), hoster.encode(message))
            self.assertEqual(decode_packets(counter.encode(["cptR"]))[0], counter.value)

    def test_captcha_response_does_not_advance_counter(self) -> None:
        counter = AhNum()
        self.assertEqual(counter.for_opcode("load"), 37)
        self.assertEqual(counter.for_opcode("cptR"), 37)
        self.assertEqual(counter.for_opcode("po"), 74)

    def test_first_load_golden_frame(self) -> None:
        self.assertEqual(AhNum().encode(["load"]), bytes.fromhex("91 a4 6c 6f 61 64 02 05"))

    def test_spawn_bootstrap_selects_team_by_default(self) -> None:
        with patch.dict("os.environ", {}, clear=True):
            messages = initial_player_messages()
        opcodes = [message[0] for message in messages]
        self.assertNotIn("sb", opcodes)
        self.assertEqual(opcodes.count("en"), 2)
        self.assertEqual(messages[opcodes.index("cd")], ["cd", "t", 1])
        self.assertEqual(messages[opcodes.index("cd", opcodes.index("cd") + 1)], ["cd", "c", {"c": 2, "s": None}])


if __name__ == "__main__":
    unittest.main()
