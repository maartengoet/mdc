package emdx

import (
	"bytes"
	"testing"
)

func TestPackPayload(t *testing.T) {
	got := packPayload(0x11, 0x00, []byte{0x01})
	want := []byte{0xAA, 0x11, 0x00, 0x01, 0x01, 0x13}
	if !bytes.Equal(got, want) {
		t.Fatalf("packPayload() = % X, want % X", got, want)
	}
}

func TestReadResponse(t *testing.T) {
	response := []byte{0xAA, 0xFF, 0x00, 0x03, 0x41, 0x11, 0x01}
	response = append(response, checksum(response[1:]))

	data, err := readResponse(bytes.NewReader(response), 0x00, 0x11)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(data, []byte{0x01}) {
		t.Fatalf("data = % X, want 01", data)
	}
}

func TestSetContentDownloadPayload(t *testing.T) {
	url := "http://192.168.1.10:3000/content.json"
	data := append([]byte{0x53, 0x80, byte(len(url))}, []byte(url)...)
	got := packPayload(0xC7, 0x00, data)

	if got[0] != 0xAA || got[1] != 0xC7 {
		t.Fatalf("unexpected frame prefix: % X", got[:2])
	}
	if got[3] != byte(len(url)+3) {
		t.Fatalf("data length = %d, want %d", got[3], len(url)+3)
	}
	if got[4] != 0x53 || got[5] != 0x80 || got[6] != byte(len(url)) {
		t.Fatalf("unexpected content command payload: % X", got[4:7])
	}
}
