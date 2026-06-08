package emdx

import (
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"strconv"
	"time"
)

const (
	defaultMDCPort = 1515
	tlsStartBanner = "MDCSTART<<TLS>>"
	authPassBanner = "MDCAUTH<<PASS>>"
	authFailPrefix = "MDCAUTH<<FAIL:"
)

type Client struct {
	Host      string
	Port      int
	DisplayID byte
	Pin       string
	Timeout   time.Duration

	conn net.Conn
}

type BatteryState struct {
	BatteryPercent       int
	BatteryWarningEnable bool
	PluggedIn            bool
	Raw                  []byte
}

func (c *Client) normalizedPort() int {
	if c.Port == 0 {
		return defaultMDCPort
	}
	return c.Port
}

func (c *Client) normalizedTimeout() time.Duration {
	if c.Timeout == 0 {
		return 30 * time.Second
	}
	return c.Timeout
}

func (c *Client) Connect() error {
	if c.conn != nil {
		return nil
	}
	if c.Host == "" {
		return fmt.Errorf("host is required")
	}
	if c.Pin == "" {
		return fmt.Errorf("pin is required")
	}

	timeout := c.normalizedTimeout()
	address := net.JoinHostPort(c.Host, strconv.Itoa(c.normalizedPort()))
	plain, err := net.DialTimeout("tcp", address, timeout)
	if err != nil {
		return err
	}

	if err := plain.SetDeadline(time.Now().Add(timeout)); err != nil {
		_ = plain.Close()
		return err
	}

	banner := make([]byte, len(tlsStartBanner))
	if _, err := io.ReadFull(plain, banner); err != nil {
		_ = plain.Close()
		return fmt.Errorf("read TLS banner: %w", err)
	}
	if string(banner) != tlsStartBanner {
		_ = plain.Close()
		return fmt.Errorf("unexpected TLS banner %q", string(banner))
	}

	secure := tls.Client(plain, &tls.Config{
		ServerName:         c.Host,
		InsecureSkipVerify: true,
	})
	if err := secure.Handshake(); err != nil {
		_ = secure.Close()
		return fmt.Errorf("TLS handshake: %w", err)
	}

	if _, err := secure.Write([]byte(c.Pin)); err != nil {
		_ = secure.Close()
		return fmt.Errorf("send PIN: %w", err)
	}

	auth := make([]byte, len(authPassBanner))
	if _, err := io.ReadFull(secure, auth); err != nil {
		_ = secure.Close()
		return fmt.Errorf("read auth response: %w", err)
	}
	switch {
	case string(auth) == authPassBanner:
		c.conn = secure
		return nil
	case string(auth[:len(authFailPrefix)]) == authFailPrefix:
		rest := make([]byte, 5)
		if _, err := io.ReadFull(secure, rest); err != nil {
			_ = secure.Close()
			return fmt.Errorf("read auth fail response: %w", err)
		}
		_ = secure.Close()
		return fmt.Errorf("authentication failed: %s%s", string(auth), string(rest))
	default:
		_ = secure.Close()
		return fmt.Errorf("unexpected auth response %q", string(auth))
	}
}

func (c *Client) Close() error {
	if c.conn == nil {
		return nil
	}
	conn := c.conn
	c.conn = nil
	return conn.Close()
}

func (c *Client) SendCommand(command byte, data []byte) ([]byte, error) {
	if err := c.Connect(); err != nil {
		return nil, err
	}
	if err := c.conn.SetDeadline(time.Now().Add(c.normalizedTimeout())); err != nil {
		return nil, err
	}

	request := packPayload(command, c.DisplayID, data)
	if _, err := c.conn.Write(request); err != nil {
		return nil, err
	}
	return readResponse(c.conn, c.DisplayID, command)
}

func (c *Client) SetContentDownloadURL(url string) error {
	if url == "" {
		return fmt.Errorf("url is required")
	}
	if len([]byte(url)) > 255 {
		return fmt.Errorf("url is too long for MDC content download: %d bytes", len([]byte(url)))
	}
	data := append([]byte{0x53, 0x80, byte(len([]byte(url)))}, []byte(url)...)
	_, err := c.SendCommand(0xC7, data)
	return err
}

func (c *Client) GetSerialNumber() (string, error) {
	data, err := c.SendCommand(0x0B, nil)
	if err != nil {
		return "", err
	}
	return string(trimTrailingNUL(data)), nil
}

func (c *Client) GetSoftwareVersion() (string, error) {
	data, err := c.SendCommand(0x0E, nil)
	if err != nil {
		return "", err
	}
	return string(trimTrailingNUL(data)), nil
}

func (c *Client) GetDeviceName() (string, error) {
	data, err := c.SendCommand(0x67, nil)
	if err != nil {
		return "", err
	}
	return string(trimTrailingNUL(data)), nil
}

func (c *Client) GetPowerState() (string, error) {
	data, err := c.SendCommand(0x11, nil)
	if err != nil {
		return "", err
	}
	if len(data) == 0 {
		return "", fmt.Errorf("empty power state response")
	}
	switch data[0] {
	case 0x00:
		return "off", nil
	case 0x01:
		return "on", nil
	case 0x02:
		return "reboot", nil
	default:
		return "", fmt.Errorf("unknown power state 0x%02X", data[0])
	}
}

func (c *Client) GetBatteryState() (BatteryState, error) {
	data, err := c.SendCommand(0x1B, []byte{0x73})
	if err != nil {
		return BatteryState{}, err
	}
	state := BatteryState{Raw: append([]byte{}, data...)}
	if len(data) > 4 {
		state.BatteryPercent = int(data[4])
	}
	if len(data) > 2 {
		state.BatteryWarningEnable = data[2] == 0x01
	}
	if len(data) > 6 {
		state.PluggedIn = data[6] == 0x02
	}
	return state, nil
}

func trimTrailingNUL(data []byte) []byte {
	for len(data) > 0 && data[len(data)-1] == 0x00 {
		data = data[:len(data)-1]
	}
	return data
}
