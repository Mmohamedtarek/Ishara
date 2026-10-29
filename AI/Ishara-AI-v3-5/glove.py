"""
glove.py — الكلام مع الجلوف على الـ Serial (مشترك بين record.py و live.py)
--------------------------------------------------------------------------
- بيلاقي البورت لوحده (Windows: COM3، COM5 ... / Ubuntu: /dev/ttyACM0)
- بيستنى البورد تقوم بعد ما البورت يتفتح (الـ DevKit بيعمل reset)
- بيتأكد إن الـ raw stream شغال (الأسطر اللي فيها 12 رقم)
- بيطلب المعايرة من الجلوف بحرف j وبيقرا سطر #CAL
"""
import time

from common import parse_glove_cal

BAUD = 115200
ESPRESSIF_VID = 0x303A                                # ESP32-S3 native USB (Windows: "USB Serial Device (COM5)")
UART_VIDS = (0x10C4, 0x1A86)                          # CP210x (Silicon Labs) و CH340 / CH343 (WCH) على الـ DevKit
PORT_HELP = ("حدد البورت بنفسك: python record.py water ahmed COM5   أو   python live.py --port COM5\n"
             "  (على Windows: Device Manager ← Ports (COM & LPT). على Ubuntu: /dev/ttyACM0 أو /dev/ttyUSB0)")


def find_port():
    from serial.tools import list_ports
    ports = list(list_ports.comports())
    for p in ports:                                   # ESP32-S3 (Espressif USB)
        if p.vid == ESPRESSIF_VID:
            return p.device
    for p in ports:                                   # DevKit UART (CP2102 / CH343) بالـ VID، نفس الكلام على Windows و Ubuntu
        if p.vid in UART_VIDS:
            return p.device
    for p in ports:                                   # أي USB serial تاني: Ubuntu بالاسم، Windows بوصف الدرايفر
        desc = f"{p.description or ''} {p.hwid or ''}".upper()
        if p.device.startswith(("/dev/ttyACM", "/dev/ttyUSB")) or "USB" in desc:
            return p.device
    # بورتات Windows اللي جوه الجهاز نفسه (COM1، Intel AMT SOL، Bluetooth) عمرها ما تبقى الجلوف: الجلوف دايمًا USB
    real = [p for p in ports if not (p.hwid or "").upper().startswith(("PCI\\", "ACPI\\", "BTHENUM\\"))
            and "BLUETOOTH" not in (p.description or "").upper()]
    if len(real) == 1:
        return real[0].device
    names = ", ".join(f"{p.device} ({p.description})" if p.description and p.description != "n/a" else p.device
                      for p in ports) or "مفيش"
    raise SystemExit(f"مش لاقي الجلوف. البورتات الموجودة: {names}\n"
                     "اتأكد إن الجلوف متوصل بكابل داتا (مش شحن بس)، ولو بورد بـ CP210x أو CH340 اتأكد إن الدرايفر متسطب.\n"
                     + PORT_HELP)


def open_glove(port=None):
    import serial
    port = port or find_port()
    try:
        ser = serial.Serial(port, BAUD, timeout=0.5)
    except serial.SerialException as e:
        raise SystemExit(f"مش قادر أفتح البورت {port}: {e}\n"
                         "  - لو البورت مستخدم (Serial Monitor بتاع Arduino، أو التطبيق، أو سكريبت تاني) اقفله الأول.\n"
                         "  - على Ubuntu لو Permission denied: sudo usermod -aG dialout $USER واعمل logout.\n"
                         + PORT_HELP)
    print(f"متوصل على {port} ... ثانيتين لحد البورد ما تقوم")
    time.sleep(2.0)                                   # فتح البورت بيعمل reset للـ DevKit
    ser.reset_input_buffer()
    return ser


def read_line(ser):
    return ser.readline().decode(errors="ignore").strip()


def is_row(line):
    """سطر داتا = 12 رقم: seq + 5 flex + 6 IMU. أي رسالة تانية من الجلوف بتبدأ بـ #"""
    parts = line.split(",")
    if len(parts) != 12:
        return None
    try:
        return [int(float(v)) for v in parts]
    except ValueError:
        return None


def _rows_within(ser, seconds):
    end, n = time.time() + seconds, 0
    while time.time() < end:
        if is_row(read_line(ser)):
            n += 1
    return n


def ensure_stream(ser):
    """لو الجلوف مش باعت داتا (الـ stream مقفول)، نبعتله s عشان يشغّله"""
    if _rows_within(ser, 0.6) >= 10:
        return True
    ser.write(b"s")
    if _rows_within(ser, 0.8) >= 10:
        return True
    ser.write(b"s")                                   # يمكن كان شغال واتقفل، نرجّعه
    return _rows_within(ser, 0.8) >= 10


def request_cal(ser, timeout=3.0):
    """
    بيبعت j ويستنى سطر #CAL. بيرجّع dict المعايرة، أو None لو الجلوف مش متعاير.
    الـ raw stream بيفضل شغال عادي، والسطر ده بيبدأ بـ # فمش هيتلخبط مع الداتا.
    """
    ser.reset_input_buffer()
    ser.write(b"j")
    end = time.time() + timeout
    while time.time() < end:
        line = read_line(ser)
        if line.startswith("#CAL"):
            try:
                return parse_glove_cal(line)
            except (ValueError, KeyError) as e:
                print(f"سطر #CAL مش مفهوم ({e}): {line[:120]}")
                return None
        if "NOT CALIBRATED" in line.upper():
            return None
    return None
