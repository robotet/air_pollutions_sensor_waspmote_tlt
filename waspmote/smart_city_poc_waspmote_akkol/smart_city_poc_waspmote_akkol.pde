/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *  Noise and air pollution monitoring sensor firmware
 *  For Libelium Plug&Sense Smart City PRO
 *  2019, Alisher Khassanov <alisher@aira.life>
 *  BSD 3-Clause License
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * 
 *  Wiring:
 *  - SOCKET_A : Noise
 *  - SOCKET_B : CO2
 *  - SOCKET_C : CO
 *  - SOCKET_D : Particle Monitor PM-X
 *  - SOCKET_E : BME200 Temperature, humidity, pressure sensor
 *  - SOCKET_F : NC
 *
 *  Secrets:
 *  File "secrets.h" must contain ed25519 keys.
 *  - uint8_t signing_key[32] = {0x01, 0x02, ... 0x20},    // private key
 *  - uint8_t verifying_key[32] = {0x01, 0x02, ... 0x20}.  // public key
 *  
 *  Signature verification tips:
 *  - signing sizeof(frame.buffer) message you sign an array of MAX_LENGTH size with trailing zeros;
 *  - if you append signature as a new field to a frame, your frame will have incremented "Num of Fields" value (5th byte)
 *  
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

#include "secrets.h"
#include <Ed25519.h> // https://github.com/khssnv/waspmote_ed25519
#include <WaspSensorCities_PRO.h>
#include <WaspPM.h>
#include <WaspFrame.h>
#include <Wasp4G.h>

// IDENTIFICATION
/////////////////////////////////////
char mote_ID[] = "AKK01";
uint8_t signature[64];
uint8_t* privateKey = signing_key;  // from "secrets.h"
uint8_t* publicKey = verifying_key; // from "secrets.h"
/////////////////////////////////////

// SERVER
/////////////////////////////////////////
char host[] = "atmosensors.aira.life";
uint16_t port = 3008;
uint8_t socketId = Wasp4G::CONNECTION_1;
uint8_t socketIndex;
char apn[] = "";
/////////////////////////////////////////

// SENSORS
//////////////////////////////////////////////////////////////////////////////
// PM is PM object
bmeCitiesSensor bme(SOCKET_E);
Gas probeCO2(SOCKET_B);
Gas probeCO(SOCKET_C);

float temperature;        // ??C
float humidity;           // %RH
float pressure;           // Pa
float concentrationCO;    // ppm
float concentrationCO2;   // ppm
//////////////////////////////////////////////////////////////////////////////

// COMMUNICATION
/////////////////////////////////////
uint32_t RESPONSE_TIMEOUT_MS = 5000;
char send_buffer[400];
/////////////////////////////////////

uint8_t error;
uint8_t maxRetry = 3;

void setupTime();
int measurePM();

void setup()
{
  USB.ON();
  USB.println(F("Smart City PRO starting..."));
  USB.println(F("You may find source code at: https://github.com/airalab/air_pollutions_sensor_waspmote_tlt"));
  USB.println(F("Common project of VKPROJECT and Airalab"));
  USB.println(F("Contacts: Alisher Khassanov, alisher@aira.life, +79649893646, +77058089667"));
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
  _4G.show_APN();

  probeCO.ON();
  probeCO2.ON();
  
  USB.println(F("Enter deep sleep mode to wait 2 min for gas sensors heating time..."));
  delay(2*60);
  //PWR.deepSleep("00:00:02:00", RTC_OFFSET, RTC_ALM1_MODE1, ALL_ON);
  USB.ON();
  pinMode(GP_I2C_MAIN_EN, OUTPUT); // configure I2C bus to read sensors
  digitalWrite(GP_I2C_MAIN_EN, HIGH); // enable I2C bus
  bme.ON();
  noise.configure();  // enable noise sensor
  
  USB.println(F("Setup complete."));
}

void loop()
{
  USB.println(F("***************************************"));
  USB.print(F("Time [Day of week, YY/MM/DD, hh:mm:ss]: "));
  USB.println(RTC.getTime());
  
  USB.println(F("Querying sensors..."));
  frame.createFrame(ASCII, mote_ID);
  // frame.addSensor(SENSOR_GMT, RTC.getTime()); // #TODO: on setup NTP RTC time update
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());
  //digitalWrite(GP_I2C_MAIN_EN, HIGH); // enable I2C bus
  
  temperature = bme.getTemperature();
  humidity = bme.getHumidity();
  pressure = bme.getPressure();
  concentrationCO  = probeCO.getConc(temperature);
  concentrationCO2 = probeCO2.getConc(temperature);
  noise.getSPLA(SLOW_MODE);

  USB.print(F("Temperature: "));
  USB.print(temperature);
  USB.println(F(" Celsius degrees"));
  USB.print(F("RH: "));
  USB.print(humidity);
  USB.println(F(" %"));
  USB.print(F("Pressure: "));
  USB.print(pressure);
  USB.println(F(" Pa"));
  USB.print(F("Gas concentration CO: "));
  USB.print(concentrationCO);
  USB.println(F(" ppm"));
  USB.print(F("Gas concentration CO2: "));
  USB.print(concentrationCO2);
  USB.println(F(" ppm"));

  frame.addSensor(SENSOR_CITIES_PRO_TC, temperature);
  frame.addSensor(SENSOR_CITIES_PRO_HUM, humidity);
  frame.addSensor(SENSOR_CITIES_PRO_PRES, pressure);
  frame.addSensor(SENSOR_CITIES_PRO_NOISE, noise.SPLA);
  frame.addSensor(SENSOR_CITIES_PRO_CO, concentrationCO);
  frame.addSensor(SENSOR_CITIES_PRO_CO2, concentrationCO2);
  
  PM.ON();
  if (measurePM() == 1) {
    USB.print(F("PM 1: "));
    USB.print(PM._PM1);
    USB.println(F(" ug/m3"));
    USB.print(F("PM 2.5: "));
    USB.print(PM._PM2_5);
    USB.println(F(" ug/m3"));
    USB.print(F("PM 10: "));
    USB.print(PM._PM10);
    USB.println(F(" ug/m3"));
    frame.addSensor(SENSOR_CITIES_PRO_PM1, PM._PM1);
    frame.addSensor(SENSOR_CITIES_PRO_PM2_5, PM._PM2_5);
    frame.addSensor(SENSOR_CITIES_PRO_PM10, PM._PM10);
  }
  PM.OFF();

  // print frame to serial
  frame.showFrame();

  //digitalWrite(GP_I2C_MAIN_EN, LOW); // disable I2C bus

  Ed25519::sign(signature, privateKey, publicKey, frame.buffer, frame.length); // sign message

  // 64 byte signature in hex (128 chars)
  for(uint8_t i = 0; i < 64; ++i)
    sprintf(send_buffer + 2*i, "%02X", signature[i]);

  // ASCII frame data
  sprintf(send_buffer + 128, "%s", frame.buffer);

  _4G.ON();
  USB.println(F("Sending data..."));

  for (;;) {
    error = _4G.openSocketClient(socketId, Wasp4G::UDP, host, port);
    if (error != 0) {
      USB.print(F("Connection open error. Code: "));
      USB.println(error, DEC);
      continue;
    }

    error = _4G.send(socketId, send_buffer);
    if (error != 0) {
      USB.print(F("Sending error. Code: "));
      USB.println(error, DEC);
      _4G.closeSocketClient(socketId);
      continue;
    }

    break;
  }

  USB.println(F("Data sent successfully."));
  _4G.OFF();

  //PWR.deepSleep("00:00:00:20", RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
  //USB.ON();
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

int measurePM() // returns 1 if OK, anything else if a sensor error code
{
  uint8_t measurePMerror = 0; // 1 - OK, other - not OK
  uint8_t retry = 1; 
  while (measurePMerror != 1) {
    if (retry > maxRetry) {
      USB.print(F("Error reading PM sensor. Error code: "));
      USB.println(measurePMerror, DEC);
      break;
    }
    measurePMerror = PM.getPM(10000, 10000);
    retry++;
  }
  return measurePMerror;
}
