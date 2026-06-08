package emdx

import (
	"encoding/hex"
	"errors"
	"fmt"
	"io"
)

const (
	headerCode   byte = 0xAA
	responseCode byte = 0xFF
	ackCode      byte = 0x41
	nakCode      byte = 0x4E
)

var (
	ErrNAK              = errors.New("negative acknowledgement")
	ErrChecksumMismatch = errors.New("checksum mismatch")
)

type NAKError struct {
	Command byte
	Code    byte
}

func (e NAKError) Error() string {
	return fmt.Sprintf("%v for command 0x%02X with error code 0x%02X", ErrNAK, e.Command, e.Code)
}

func checksum(payload []byte) byte {
	var sum int
	for _, value := range payload {
		sum += int(value)
	}
	return byte(sum % 256)
}

func packPayload(command byte, displayID byte, data []byte) []byte {
	payload := make([]byte, 0, 5+len(data))
	payload = append(payload, headerCode, command, displayID, byte(len(data)))
	payload = append(payload, data...)
	payload = append(payload, checksum(payload[1:]))
	return payload
}

func readResponse(reader io.Reader, displayID byte, expectedCommand byte) ([]byte, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(reader, header); err != nil {
		return nil, err
	}
	if header[0] != headerCode {
		return nil, fmt.Errorf("unexpected response header 0x%02X", header[0])
	}
	if header[1] != responseCode {
		return nil, fmt.Errorf("unexpected response command 0x%02X", header[1])
	}
	if header[2] != displayID {
		return nil, fmt.Errorf("unexpected display id 0x%02X", header[2])
	}

	length := int(header[3])
	body := make([]byte, length+1)
	if _, err := io.ReadFull(reader, body); err != nil {
		return nil, err
	}

	frame := append(append([]byte{}, header...), body...)
	if got, want := frame[len(frame)-1], checksum(frame[1:len(frame)-1]); got != want {
		return nil, fmt.Errorf("%w: got 0x%02X, expected 0x%02X in %s", ErrChecksumMismatch, got, want, hex.EncodeToString(frame))
	}
	if length < 2 {
		return nil, fmt.Errorf("response data length too short: %d", length)
	}

	ackOrNak := frame[4]
	command := frame[5]
	if command != expectedCommand {
		return nil, fmt.Errorf("unexpected response command 0x%02X, expected 0x%02X", command, expectedCommand)
	}

	data := frame[6 : len(frame)-1]
	switch ackOrNak {
	case ackCode:
		return data, nil
	case nakCode:
		code := byte(0)
		if len(data) > 0 {
			code = data[0]
		}
		return nil, NAKError{Command: command, Code: code}
	default:
		return nil, fmt.Errorf("unexpected ACK/NAK byte 0x%02X", ackOrNak)
	}
}
