import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class City {
  const City(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

class Weather {
  Weather({
    required this.temperature,
    required this.code,
    required this.time,
  });

  final double temperature;
  final int code;
  final String time;

  factory Weather.fromJson(Map<String, dynamic> json) {
    return Weather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      code: (json['weather_code'] as num).toInt(),
      time: json['time'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'temperature_2m': temperature,
        'weather_code': code,
        'time': time,
      };
}

Future<Weather> fetchWeather(City city) async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${city.latitude}&longitude=${city.longitude}'
    '&current=temperature_2m,weather_code'
    '&timezone=Africa%2FKigali',
  );

  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw Exception('Failed to load weather');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return Weather.fromJson(data['current'] as Map<String, dynamic>);
}
