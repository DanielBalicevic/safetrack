// HTTP(S) client using the SIM7000 modem's built-in stack
// (AT+SHCONF / SHCONN / SHREQ / SHREAD).
//
// TinyGSM's socket read path (AT+CARECV) does not work on SIM7000G firmware
// R1529, so the whole request is delegated to the modem. Assumes the network
// and GPRS context are already up. Every AT command is logged.
#ifndef SIM7000_HTTP_H
#define SIM7000_HTTP_H

#include <Arduino.h>

// Google Trust Services root certificates, used only by the HTTP diagnostics
// build. *.cloudfunctions.net chains to GTS Root R1 cross-signed by GlobalSign,
// so the intermediate (WR2) and the cross-signed root are included as well.

// GTS Root R1 (self-signed), valid until 2036-06-22. https://pki.goog/repo/certs/gtsr1.pem
static const char GTS_ROOT_R1_PEM[] =
    "-----BEGIN CERTIFICATE-----\n"
    "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\n"
    "bP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c\n"
    "-----END CERTIFICATE-----\n";

static const char* GTS_ROOT_R1_NAME = "gtsr1.pem";

// WR2 intermediate (Google Trust Services), valid until 2029-02-20.
static const char WR2_PEM[] =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIFCzCCAvOgAwIBAgIQf/AFoHxM3tEArZ1mpRB7mDANBgkqhkiG9w0BAQsFADBH\n"
    "MQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExM\n"
    "QzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMjMxMjEzMDkwMDAwWhcNMjkwMjIw\n"
    "MTQwMDAwWjA7MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVR29vZ2xlIFRydXN0IFNl\n"
    "cnZpY2VzMQwwCgYDVQQDEwNXUjIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK\n"
    "AoIBAQCp/5x/RR5wqFOfytnlDd5GV1d9vI+aWqxG8YSau5HbyfsvAfuSCQAWXqAc\n"
    "+MGr+XgvSszYhaLYWTwO0xj7sfUkDSbutltkdnwUxy96zqhMt/TZCPzfhyM1IKji\n"
    "aeKMTj+xWfpgoh6zySBTGYLKNlNtYE3pAJH8do1cCA8Kwtzxc2vFE24KT3rC8gIc\n"
    "LrRjg9ox9i11MLL7q8Ju26nADrn5Z9TDJVd06wW06Y613ijNzHoU5HEDy01hLmFX\n"
    "xRmpC5iEGuh5KdmyjS//V2pm4M6rlagplmNwEmceOuHbsCFx13ye/aoXbv4r+zgX\n"
    "FNFmp6+atXDMyGOBOozAKql2N87jAgMBAAGjgf4wgfswDgYDVR0PAQH/BAQDAgGG\n"
    "MB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjASBgNVHRMBAf8ECDAGAQH/\n"
    "AgEAMB0GA1UdDgQWBBTeGx7teRXUPjckwyG77DQ5bUKyMDAfBgNVHSMEGDAWgBTk\n"
    "rysmcRorSCeFL1JmLO/wiRNxPjA0BggrBgEFBQcBAQQoMCYwJAYIKwYBBQUHMAKG\n"
    "GGh0dHA6Ly9pLnBraS5nb29nL3IxLmNydDArBgNVHR8EJDAiMCCgHqAchhpodHRw\n"
    "Oi8vYy5wa2kuZ29vZy9yL3IxLmNybDATBgNVHSAEDDAKMAgGBmeBDAECATANBgkq\n"
    "hkiG9w0BAQsFAAOCAgEARXWL5R87RBOWGqtY8TXJbz3S0DNKhjO6V1FP7sQ02hYS\n"
    "TL8Tnw3UVOlIecAwPJQl8hr0ujKUtjNyC4XuCRElNJThb0Lbgpt7fyqaqf9/qdLe\n"
    "SiDLs/sDA7j4BwXaWZIvGEaYzq9yviQmsR4ATb0IrZNBRAq7x9UBhb+TV+PfdBJT\n"
    "DhEl05vc3ssnbrPCuTNiOcLgNeFbpwkuGcuRKnZc8d/KI4RApW//mkHgte8y0YWu\n"
    "ryUJ8GLFbsLIbjL9uNrizkqRSvOFVU6xddZIMy9vhNkSXJ/UcZhjJY1pXAprffJB\n"
    "vei7j+Qi151lRehMCofa6WBmiA4fx+FOVsV2/7R6V2nyAiIJJkEd2nSi5SnzxJrl\n"
    "Xdaqev3htytmOPvoKWa676ATL/hzfvDaQBEcXd2Ppvy+275W+DKcH0FBbX62xevG\n"
    "iza3F4ydzxl6NJ8hk8R+dDXSqv1MbRT1ybB5W0k8878XSOjvmiYTDIfyc9acxVJr\n"
    "Y/cykHipa+te1pOhv7wYPYtZ9orGBV5SGOJm4NrB3K1aJar0RfzxC3ikr7Dyc6Qw\n"
    "qDTBU39CluVIQeuQRgwG3MuSxl7zRERDRilGoKb8uY45JzmxWuKxrfwT/478JuHU\n"
    "/oTxUFqOl2stKnn7QGTq8z29W+GgBLCXSBxC9epaHM0myFH/FJlniXJfHeytWt0=\n"
    "-----END CERTIFICATE-----\n";
static const char* WR2_NAME = "wr2.pem";


// GTS Root R1 cross-signed by GlobalSign Root CA, valid until 2028-01-28.
static const char GTS_ROOT_R1_XSIGN_PEM[] =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIFYjCCBEqgAwIBAgIQd70NbNs2+RrqIQ/E8FjTDTANBgkqhkiG9w0BAQsFADBX\n"
    "MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEQMA4GA1UE\n"
    "CxMHUm9vdCBDQTEbMBkGA1UEAxMSR2xvYmFsU2lnbiBSb290IENBMB4XDTIwMDYx\n"
    "OTAwMDA0MloXDTI4MDEyODAwMDA0MlowRzELMAkGA1UEBhMCVVMxIjAgBgNVBAoT\n"
    "GUdvb2dsZSBUcnVzdCBTZXJ2aWNlcyBMTEMxFDASBgNVBAMTC0dUUyBSb290IFIx\n"
    "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAthECix7joXebO9y/lD63\n"
    "ladAPKH9gvl9MgaCcfb2jH/76Nu8ai6Xl6OMS/kr9rH5zoQdsfnFl97vufKj6bwS\n"
    "iV6nqlKr+CMny6SxnGPb15l+8Ape62im9MZaRw1NEDPjTrETo8gYbEvs/AmQ351k\n"
    "KSUjB6G00j0uYODP0gmHu81I8E3CwnqIiru6z1kZ1q+PsAewnjHxgsHA3y6mbWwZ\n"
    "DrXYfiYaRQM9sHmklCitD38m5agI/pboPGiUU+6DOogrFZYJsuB6jC511pzrp1Zk\n"
    "j5ZPaK49l8KEj8C8QMALXL32h7M1bKwYUH+E4EzNktMg6TO8UpmvMrUpsyUqtEj5\n"
    "cuHKZPfmghCN6J3Cioj6OGaK/GP5Afl4/Xtcd/p2h/rs37EOeZVXtL0m79YB0esW\n"
    "CruOC7XFxYpVq9Os6pFLKcwZpDIlTirxZUTQAs6qzkm06p98g7BAe+dDq6dso499\n"
    "iYH6TKX/1Y7DzkvgtdizjkXPdsDtQCv9Uw+wp9U7DbGKogPeMa3Md+pvez7W35Ei\n"
    "Eua++tgy/BBjFFFy3l3WFpO9KWgz7zpm7AeKJt8T11dleCfeXkkUAKIAf5qoIbap\n"
    "sZWwpbkNFhHax2xIPEDgfg1azVY80ZcFuctL7TlLnMQ/0lUTbiSw1nH69MG6zO0b\n"
    "9f6BQdgAmD06yK56mDcYBZUCAwEAAaOCATgwggE0MA4GA1UdDwEB/wQEAwIBhjAP\n"
    "BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTkrysmcRorSCeFL1JmLO/wiRNxPjAf\n"
    "BgNVHSMEGDAWgBRge2YaRQ2XyolQL30EzTSo//z9SzBgBggrBgEFBQcBAQRUMFIw\n"
    "JQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnBraS5nb29nL2dzcjEwKQYIKwYBBQUH\n"
    "MAKGHWh0dHA6Ly9wa2kuZ29vZy9nc3IxL2dzcjEuY3J0MDIGA1UdHwQrMCkwJ6Al\n"
    "oCOGIWh0dHA6Ly9jcmwucGtpLmdvb2cvZ3NyMS9nc3IxLmNybDA7BgNVHSAENDAy\n"
    "MAgGBmeBDAECATAIBgZngQwBAgIwDQYLKwYBBAHWeQIFAwIwDQYLKwYBBAHWeQIF\n"
    "AwMwDQYJKoZIhvcNAQELBQADggEBADSkHrEoo9C0dhemMXoh6dFSPsjbdBZBiLg9\n"
    "NR3t5P+T4Vxfq7vqfM/b5A3Ri1fyJm9bvhdGaJQ3b2t6yMAYN/olUazsaL+yyEn9\n"
    "WprKASOshIArAoyZl+tJaox118fessmXn1hIVw41oeQa1v1vg4Fv74zPl6/AhSrw\n"
    "9U5pCZEt4Wi4wStz6dTZ/CLANx8LZh1J7QJVj2fhMtfTJr9w4z30Z209fOU0iOMy\n"
    "+qduBmpvvYuR7hZL6Dupszfnw0Skfths18dG9ZKb59UhvmaSGZRVbNQpsg3BZlvi\n"
    "d0lIKO2d1xozclOzgjXPYovJJIultzkMu34qQb9Sz/yilrbCgj8=\n"
    "-----END CERTIFICATE-----\n";
static const char* GTS_ROOT_R1_XSIGN_NAME = "gtsr1x.pem";
struct ShResponse {
  int    status = -1;   // HTTP status, or negative if the request failed earlier
  String body;          // response body, truncated
  String step;          // last step reached, for diagnostics
};

class Sim7000Http {
 public:
  Sim7000Http(Stream& at, Stream& log) : _at(at), _log(log) {}

  // Skip the certificate validity period check (the modem clock may be wrong).
  bool ignoreRtcTime = true;

  bool syncClockNtp() {
    drain();
    at("AT+CNTPCID=1");
    at("AT+CNTP=\"pool.ntp.org\",0");
    at("AT+CNTP", "OK", 5000);
    awaitUrc("+CNTP:", 20000);
    String clk = at("AT+CCLK?");
    bool ok = clk.indexOf("+CCLK:") >= 0;
    _log.print("[CLOCK] sync "); _log.println(ok ? "ok" : "failed");
    return ok;
  }

  // Uploads a PEM certificate to the modem and registers it as a CA.
  bool loadCA(const char* pem, const char* name) {
    size_t len = strlen(pem);
    drain();
    // Release any buffer left from a previous attempt; an ERROR here is expected.
    at("AT+CFSTERM");
    if (at("AT+CFSINIT").indexOf("OK") < 0) {
      _log.println("[CA] CFSINIT failed.");
      return false;
    }
    // On the SIM7000 the command is CFSWFILE (CFSWRITE is SIM7070/7080 only).
    // Directory 3 is /customer/, mode 0 overwrites.
    _log.print(">> AT+CFSWFILE=3,\""); _log.print(name);
    _log.print("\",0,"); _log.print(len); _log.println(",10000");
    _at.print("AT+CFSWFILE=3,\""); _at.print(name);
    _at.print("\",0,"); _at.print(len); _at.print(",10000\r\n");
    if (await("DOWNLOAD", 5000).indexOf("DOWNLOAD") < 0) {
      _log.println("[CA] no DOWNLOAD prompt.");
      at("AT+CFSTERM");
      return false;
    }
    _at.write((const uint8_t*)pem, len);   // exactly `len` bytes
    String w = await("OK", 15000);
    at("AT+CFSTERM");
    String c = at(String("AT+CSSLCFG=\"convert\",2,\"") + name + "\"", "OK", 10000);
    bool ok = (w.indexOf("OK") >= 0) && (c.indexOf("OK") >= 0);
    _log.print("[CA] load '"); _log.print(name); _log.print("' ");
    _log.println(ok ? "ok" : "failed");
    return ok;
  }

  // Performs an HTTP(S) request. With ssl and a caName the server certificate
  // is validated against that CA.
  ShResponse request(const String& host, uint16_t port, bool ssl,
                     const char* method, const char* path,
                     const char* contentType, const char* extraName,
                     const char* extraValue, const String& body,
                     const char* caName) {
    ShResponse r;
    drain();

    if (ssl) {
      r.step = "CSSLCFG";
      at("AT+CSSLCFG=\"sslversion\",1,3");   // TLS 1.2
      // Google's front end selects the certificate by SNI.
      at(String("AT+CSSLCFG=\"sni\",1,\"") + host + "\"");
      if (caName) {
        // Validation is enabled only by passing a non-empty CA name to SHSSL.
        r.step = "SHSSL (validate)";
        if (ignoreRtcTime) at("AT+CSSLCFG=\"ignorertctime\",1,1");
        at(String("AT+SHSSL=1,\"") + caName + "\"");
      } else {
        r.step = "SHSSL (no validation)";
        at("AT+SHSSL=1,\"\"");
      }
    }

    r.step = "SHCONF URL";
    String url = String(ssl ? "https://" : "http://") + host + ":" + String(port);
    if (at(String("AT+SHCONF=\"URL\",\"") + url + "\"").indexOf("OK") < 0) return r;
    at("AT+SHCONF=\"BODYLEN\",1024");
    at("AT+SHCONF=\"HEADERLEN\",350");

    r.step = "SHCONN";
    if (at("AT+SHCONN", "OK", 60000).indexOf("OK") < 0) return r;

    r.step = "SHSTATE";
    if (at("AT+SHSTATE?").indexOf("+SHSTATE: 1") < 0) { at("AT+SHDISC"); return r; }

    r.step = "SHAHEAD";
    at("AT+SHCHEAD");
    if (contentType) at(String("AT+SHAHEAD=\"Content-Type\",\"") + contentType + "\"");
    if (extraName)   at(String("AT+SHAHEAD=\"") + extraName + "\",\"" + extraValue + "\"");

    int type = 1;  // GET
    if (strcmp(method, "POST") == 0) {
      type = 3;    // POST
      r.step = "SHBOD";
      at(String("AT+SHBOD=\"") + escapeAt(body) + "\"," + String(body.length()));
    }

    // SHREQ answers OK immediately; the result arrives later as
    // +SHREQ: "<method>",<status>,<length>
    r.step = "SHREQ";
    at(String("AT+SHREQ=\"") + path + "\"," + String(type), "OK", 10000);
    String urc = awaitUrc("+SHREQ:", 60000);
    r.status = parseInt(urc, "+SHREQ:", 1);
    int datalen = parseInt(urc, "+SHREQ:", 2);

    if (datalen > 0) {
      int toRead = datalen > 600 ? 600 : datalen;
      r.step = "SHREAD";
      String rd = at(String("AT+SHREAD=0,") + String(toRead), "OK", 15000);
      r.body = extractBody(rd);
    }

    at("AT+SHDISC");
    r.step = "OK";
    return r;
  }

 private:
  Stream& _at;
  Stream& _log;

  // Discards pending bytes (old URCs).
  void drain() {
    uint32_t t = millis();
    while (millis() - t < 120) { while (_at.available()) { _at.read(); t = millis(); } }
  }

  String at(const String& c, const char* until = "OK", uint32_t timeout = 5000) {
    _log.print(">> "); _log.println(c);
    _at.print(c); _at.print("\r\n");
    return await(until, timeout);
  }

  String await(const char* until, uint32_t timeout) {
    String buf;
    uint32_t start = millis();
    while (millis() - start < timeout) {
      while (_at.available()) {
        buf += (char)_at.read();
        if (buf.endsWith(until) || buf.endsWith("ERROR")) {
          logResp(buf);
          return buf;
        }
      }
      delay(4);
    }
    _log.print("<< [TIMEOUT] ");
    logResp(buf);
    return buf;
  }

  // Waits for `token` followed by the end of its line.
  String awaitUrc(const char* token, uint32_t timeout) {
    String buf;
    uint32_t start = millis();
    while (millis() - start < timeout) {
      while (_at.available()) {
        buf += (char)_at.read();
        int tp = buf.indexOf(token);
        if (tp >= 0 && buf.indexOf('\n', tp + (int)strlen(token)) >= 0) {
          logResp(buf);
          return buf;
        }
      }
      delay(4);
    }
    _log.print("<< [TIMEOUT URC] ");
    logResp(buf);
    return buf;
  }

  void logResp(const String& buf) {
    String s = buf;
    s.replace("\r", " ");
    s.replace("\n", " ");
    s.trim();
    _log.print("<< "); _log.println(s);
  }

  static String escapeAt(const String& in) {
    String out;
    out.reserve(in.length() + 8);
    for (size_t i = 0; i < in.length(); i++) {
      char c = in[i];
      if (c == '\\' || c == '"') out += '\\';
      out += c;
    }
    return out;
  }

  // Returns the n-th comma-separated integer after `prefix` (1-based).
  // "+SHREQ: \"POST\",200,1234" -> field 1 = 200, field 2 = 1234.
  static int parseInt(const String& resp, const char* prefix, int field) {
    int p = resp.indexOf(prefix);
    if (p < 0) return -1;
    p += strlen(prefix);
    while (field > 0) {
      int c = resp.indexOf(',', p);
      if (c < 0) return -1;
      p = c + 1;
      field--;
    }
    while (p < (int)resp.length() && resp[p] == ' ') p++;
    int val = 0; bool any = false;
    while (p < (int)resp.length() && isdigit(resp[p])) { val = val * 10 + (resp[p] - '0'); p++; any = true; }
    return any ? val : -1;
  }

  // Body between the "+SHREAD: <n>" line and the final OK.
  static String extractBody(const String& resp) {
    int p = resp.indexOf("+SHREAD:");
    if (p < 0) return "";
    int nl = resp.indexOf('\n', p);
    if (nl < 0) return "";
    String rest = resp.substring(nl + 1);
    int okp = rest.lastIndexOf("OK");
    if (okp >= 0) rest = rest.substring(0, okp);
    rest.trim();
    return rest;
  }
};

#endif  // SIM7000_HTTP_H
