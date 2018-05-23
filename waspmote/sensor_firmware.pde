/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *  Air pollution monitoring sensor firmware
 *  For Libelium Plug&Sense Smart Environment PRO
 *  April 2018, Alisher Khassanov <alisher@aira.life>
 *  BSD 3-Clause License
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *
 *  ATTENTION! Real-time clock (RTC) must be set in order to use one time password identification.
 *  Use serial interface to setup UTC time on clock.
 *
 *  Wiring:
 *  - SOCKET_A : CO low concentrations probe
 *  - SOCKET_B : NO probe
 *  - SOCKET_C : SO2 probe
 *  - SOCKET_D : Particle Monitor PM-X
 *  - SOCKET_E : BME200 Temperature, humidity, pressure sensor
 *  - SOCKET_F :
 *
 *  Secrets:
 *  File "secrets.h" must contain:
 *  - One time password private code,
 *    example uint8_t hmacKey[] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10};
 *  - TCP server SSL private key,
 *    example char certificate[] =
 *             "-----BEGIN CERTIFICATE-----\r"\
 *             "your-sertificate-here-------------------------------------------\r"\
 *             "your-sertificate-here-------------------------------------------\r"\
 *             ...
 *             "your-sertificate-here-------------------------------------------\r"\
 *             "-----END CERTIFICATE-----";
 *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

#include <Wasp4G.h>
#include <WaspFrame.h>
#include <TOTP.h> // https://github.com/khssnv/TOTP-Arduino
#include <sha1.h>
#include <BME280.h>
#include <WaspOPC_N2.h>
#include <WaspSensorGas_Pro.h>
#include "secrets.h"

// IDENTIFICATION
/////////////////////////////////////
TOTP _TOTP = TOTP(hmacKey, 10, 3600);
char mote_ID[] = "TLT01";
/////////////////////////////////////

// SERVER
/////////////////////////////////////////
char host[] = "devjs-01.corp.aira.life";
uint16_t port = 3009;
uint8_t socketId = Wasp4G::CONNECTION_1;
uint8_t socketIndex;
char apn[] = "";
/////////////////////////////////////////

// SENSORS
//////////////////////////////////////////////////////////////////////////////
// P&S! Possibilities for this sensor: SOCKET_A, SOCKET_B, SOCKET_C, SOCKET_F
// BME - Temp, Hum, Press
// OPC_N2 - PM
Gas probeCO(SOCKET_A);
Gas probeNO(SOCKET_B);
Gas probeSO2(SOCKET_C);

float temperature;        // ºC
float humidity;           // %RH
float pressure;           // Pa
int   measurePM;
float concentrationCO;    // ppm
float concentrationNO;    // ppm
float concentrationSO2;   // ppm
//////////////////////////////////////////////////////////////////////////////

uint8_t  error;

void setupTime();

void setup()
{
  USB.ON();
  USB.println(F("Smart Environment PRO starting..."));
  USB.print(F("Sensor ID: "));
  USB.println(mote_ID);
  USB.print(F("Destination Server: "));
  USB.print(host);
  USB.print(F(":"));
  USB.println(port);
  USB.print(F("Battery level: "));
  USB.print((int) PWR.getBatteryLevel());
  USB.println(F(" %"));

  RTC.ON();
  setupTime();

  _4G.set_APN(apn);
  _4G.ON();
  error = _4G.manageSSL(socketId, Wasp4G::SSL_ACTION_STORE, Wasp4G::SSL_TYPE_CA_CERT, certificate);
  if (error == 0)
  {
    USB.println(F("Set CA certificate OK"));
  }
  else
  {
    USB.print(F("Error setting CA certificate. Error="));
    USB.println(error, DEC);
  }
  _4G.OFF();

  pinMode(GP_I2C_MAIN_EN, OUTPUT);

  USB.println(F("Setup complete..."));
}

void loop()
{
  USB.println(F("***************************************"));
  USB.print(F("Time [Day of week, YY/MM/DD, hh:mm:ss]: "));
  USB.println(RTC.getTime());

  digitalWrite(GP_I2C_MAIN_EN, HIGH);
  BME.ON();
  OPC_N2.ON();
  probeCO.ON();
  probeNO.ON();
  probeSO2.ON();

  temperature = BME.getTemperature(BME280_OVERSAMP_16X, BME280_FILTER_COEFF_OFF);
  humidity = BME.getHumidity(BME280_OVERSAMP_16X);
  pressure = BME.getPressure(BME280_OVERSAMP_16X, BME280_FILTER_COEFF_OFF);
  measurePM = OPC_N2.getPM(10000, 10000);
  concentrationCO  = probeCO.getConc();
  concentrationNO  = probeNO.getConc();
  concentrationSO2 = probeSO2.getConc();

  USB.print(F("Temperature: "));
  USB.print(temperature);
  USB.println(F(" Celsius degrees"));
  USB.print(F("RH: "));
  USB.print(humidity);
  USB.println(F(" %"));
  USB.print(F("Pressure: "));
  USB.print(pressure);
  USB.println(F(" Pa"));
  USB.print(F("PM 1: "));
  USB.print(OPC_N2._PM1);
  USB.println(F(" ug/m3"));
  USB.print(F("PM 2.5: "));
  USB.print(OPC_N2._PM2_5);
  USB.println(F(" ug/m3"));
  USB.print(F("PM 10: "));
  USB.print(OPC_N2._PM10);
  USB.println(F(" ug/m3"));
  USB.print(F("Gas concentration CO: "));
  USB.print(concentrationCO);
  USB.println(F(" ppm"));
  USB.print(F("Gas concentration NO: "));
  USB.print(concentrationNO);
  USB.println(F(" ppm"));
  USB.print(F("Gas concentration SO2: "));
  USB.print(concentrationSO2);
  USB.println(F(" ppm"));

  digitalWrite(GP_I2C_MAIN_EN, LOW);
  OPC_N2.OFF();
  probeCO.OFF();
  probeNO.OFF();
  probeSO2.OFF();

  frame.createFrame(ASCII, mote_ID);
  frame.addSensor(SENSOR_GMT, RTC.getTime());
  frame.addSensor(SENSOR_STR, _TOTP.getCode(RTC.getEpochTime()));
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());
  frame.addSensor(SENSOR_GASES_PRO_TC, temperature);
  frame.addSensor(SENSOR_GASES_PRO_HUM, humidity);
  frame.addSensor(SENSOR_GASES_PRO_PRES, pressure);
  frame.addSensor(SENSOR_GASES_PRO_CO, concentrationCO);
  frame.addSensor(SENSOR_GASES_PRO_NO, concentrationNO);
  frame.addSensor(SENSOR_GASES_PRO_SO2, concentrationSO2);
  frame.addSensor(SENSOR_GASES_PRO_PM1, OPC_N2._PM1);
  frame.addSensor(SENSOR_GASES_PRO_PM2_5, OPC_N2._PM2_5);
  frame.addSensor(SENSOR_GASES_PRO_PM10, OPC_N2._PM10);
  frame.showFrame();

  USB.print(F("Free Memory: "));
  USB.print(freeMemory());
  USB.println(F(" bytes"));

  _4G.ON();
  error = _4G.openSocketSSL(socketId, host, port);
  if (error == 0)
  {
    USB.println(F("Sending data..."));
    error = _4G.sendSSL(socketId, (char*) frame.buffer);
    if (error == 0)
    {
      USB.println(F("Data sent successfully."));
    }
    else
    {
      USB.print(F("Error sending data. Code: "));
      USB.println(error, DEC);
    }
    _4G.closeSocketSSL(socketId);
  }
  else
  {
    USB.print(F("Error opening socket. Error code: "));
    USB.println(error, DEC);
  }
  _4G.OFF();

  PWR.deepSleep("00:00:01:00", RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);

}

void setupTime()
{
  USB.print(F("Current time [Day of week, YY/MM/DD, hh:mm:ss]: "));
  USB.println(RTC.getTime());
  USB.print(F("Type 's' to setup time or 'c' to continue.\n"\
              "With no input it will continue with no changes after 10 seconds: "));
  unsigned long time = 0;
  time = millis();
  while (millis() - time < 10000) // wait for input 10 sec
  {
    if (USB.available() > 0)
    {
      char val = USB.read();
      USB.println(val, BYTE);
      if (val == 's')
      {
        USB.println(F("Setting up time..."));
        USB.print(F("Type a string in format [yy:mm:dd:dw:hh:mm:ss],"\
                    "20 symbols including ':' ('dw' means 'day of week' from Sunday) :"));
        char input[21]; // 20 time symbols + string terminator
        strcpy(input, "");
        while (!USB.available()) {} // wait for input
        while (USB.available() > 0)
        {
          val = USB.read();
          snprintf(input, sizeof(input), "%s%c", input, val);
        }
        RTC.setTime(input);
        USB.println();
        USB.println(input);
        USB.print(F("Time set [Day of week, YY/MM/DD, hh:mm:ss]: "));
        USB.println(RTC.getTime());
        break;
      }
      else if (val == 'c')
      {
        USB.println(F("Continue with no changes..."));
        break;
      }
      else
      {
        USB.println(F("Unknown command, continue with no changes..."));
        break;
      }
    }

    if (millis() < time) // Condition to avoid an overflow
    {
      time = millis();
    }
  }
  USB.println();
  USB.flush(); // clear serial input buffer
}
