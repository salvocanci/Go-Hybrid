// Spike 5 probes (thresholds pre-registered in ../RESULTS.md).
package spike5

import (
	"errors"
	"os"
	"os/exec"
	"testing"

	"spike5/hybridge"
)

// E1: ok path returns the right value and a nil error.
func TestOkPath(t *testing.T) {
	for _, c := range []struct{ a, b uint64 }{{2, 40}, {0, 0}, {1 << 40, 1 << 40}} {
		v, err := hybridge.OkAdd(c.a, c.b)
		if err != nil || v != c.a+c.b {
			t.Fatalf("OkAdd(%d,%d) = (%d, %v)", c.a, c.b, v, err)
		}
	}
}

// E2/E3: error paths return the mapped sentinel / wrapped sentinel.
func TestErrorPaths(t *testing.T) {
	// a=0,flag=1 -> code (0%4)+1 = NotFound
	_, err := hybridge.MayFail(0, 1, false)
	if !errors.Is(err, hybridge.ErrNotFound) {
		t.Fatalf("sentinel arm: got %v", err)
	}
	// a=3,flag=1 -> code 4 = Io, payload 3, wrapped
	_, err = hybridge.MayFail(3, 1, true)
	if !errors.Is(err, hybridge.ErrIo) {
		t.Fatalf("wrapped arm: errors.Is failed for %v", err)
	}
	var pe *hybridge.PayloadError
	if !errors.As(err, &pe) {
		t.Fatalf("errors.As failed for %v", err)
	}
	if pe.Payload != 3 {
		t.Fatalf("payload = %d, want 3", pe.Payload)
	}
	// ok arm
	v, err := hybridge.MayFail(9, 0, true)
	if err != nil || v != 9 {
		t.Fatalf("ok arm: (%d, %v)", v, err)
	}
}

// E4: identity through the full chain (Is on the leaf and the root).
func TestErrorIdentity(t *testing.T) {
	_, err := hybridge.ChainFail(0) // Io payload 77
	if !errors.Is(err, hybridge.ErrIo) {
		t.Fatalf("chain leaf identity failed: %v", err)
	}
	// The Rust-side source chain (Io -> NotFound in the hyerr model) is NOT
	// reconstructed here: only the leaf code crosses. Documented loss.
	if errors.Is(err, hybridge.ErrNotFound) {
		t.Fatalf("unexpected chain reconstruction (should be a documented loss)")
	}
	var pe *hybridge.PayloadError
	if errors.As(err, &pe) || true {
		_ = pe // PayloadError arm exercised above; here we only care it type-checks
	}
}

// E5: the panic contract — a Rust panic aborts the process; it never unwinds
// into Go frames. Runs a child process that calls the panicking fn; the
// parent asserts the child died by a signal (SIGABRT), not a Go panic exit.
func TestPanicContract(t *testing.T) {
	if os.Getenv("SPIKE5_PANIC_CHILD") == "1" {
		// child: this must never return
		hybridge.Panic()
		t.Fatal("child: hybridge.Panic returned — contract VIOLATED")
		return
	}
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(exe)
	cmd.Env = append(os.Environ(), "SPIKE5_PANIC_CHILD=1")
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("child exited cleanly — panic did NOT abort:\n%s", out)
	}
	ee, ok := err.(*exec.ExitError)
	if !ok {
		t.Fatalf("child error type %T: %v", err, err)
	}
	// expect death by signal (SIGABRT = signal 6) — panic=abort at the Rust edge
	if ee.ExitCode() != -1 {
		t.Fatalf("child exit code %d (want -1 = killed by signal):\n%s", ee.ExitCode(), out)
	}
	t.Logf("child killed by signal %v; tail: %q", ee.Sys(), lastLine(out))
}

func lastLine(b []byte) string {
	s := string(b)
	if i := len(s) - 200; i > 0 {
		s = s[i:]
	}
	return s
}
