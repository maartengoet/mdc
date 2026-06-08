package emdx

import (
	"encoding/hex"
	"fmt"
	"net"
	"strings"
)

func WakeOnLAN(mac string) error {
	packet, err := magicPacket(mac)
	if err != nil {
		return err
	}

	conn, err := net.Dial("udp4", "255.255.255.255:9")
	if err != nil {
		return err
	}
	defer conn.Close()

	_, err = conn.Write(packet)
	return err
}

func magicPacket(mac string) ([]byte, error) {
	clean := strings.NewReplacer(":", "", "-", "", ".", "").Replace(mac)
	bytes, err := hex.DecodeString(clean)
	if err != nil || len(bytes) != 6 {
		return nil, fmt.Errorf("invalid MAC address %q", mac)
	}

	packet := make([]byte, 6+(16*6))
	for i := 0; i < 6; i++ {
		packet[i] = 0xFF
	}
	for i := 0; i < 16; i++ {
		copy(packet[6+(i*6):], bytes)
	}
	return packet, nil
}
