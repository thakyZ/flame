const Weather = require('../models/Weather');
const axios = require('axios');
const loadConfig = require('./loadConfig');

const getExternalWeather = async () => {
  const { WEATHER_API_KEY: secret, lat, long } = await loadConfig();

  // Fetch data from external API
  try {
    const res = await axios.get(
      `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${long}&appid=${secret}`
    );

    // Save weather data
    const cursor = res.data;
    const temp_c = cursor.main.temp - 273.15;
    const temp_f = temp_c * 1.8 + 32;
    const is_day = cursor.dt > cursor.sys.sunrise && cursor.dt < cursor.sys.sunset ? true : false;
    return await Weather.create({
      externalLastUpdate: 0,
      tempC: temp_c.toFixed(0),
      tempF: temp_f.toFixed(0),
      isDay: is_day,
      cloud: cursor.clouds.all,
      conditionText: cursor.weather[0].main,
      conditionCode: cursor.weather[0].id,
      humidity: cursor.main.humidity,
      windK: (cursor.wind.speed * 3.6).toFixed(0),
      windM: ((cursor.wind.speed * 3.6) * 1.609).toFixed(0),
    });
  } catch (err) {
    throw new Error('External API request failed');
  }
};

module.exports = getExternalWeather;
