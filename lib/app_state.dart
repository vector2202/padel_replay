import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  SharedPreferences? _prefs;
  Map<String, dynamic>? _activeCourt;
  DateTime? _sessionStartTime;
  String _edgeNodeIp = "192.168.0.15"; // IP por defecto

  String get edgeNodeIp => _edgeNodeIp;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _edgeNodeIp = _prefs?.getString('edge_node_ip') ?? "192.168.0.15";
    notifyListeners();
  }
  
  void setEdgeNodeIp(String ip) {
    _edgeNodeIp = ip;
    _prefs?.setString('edge_node_ip', ip);
    notifyListeners();
  }
  Map<String, dynamic>? get activeCourt {
    // Si han pasado más de 2 horas, limpiamos la sesión automáticamente
    if (_sessionStartTime != null && 
        DateTime.now().difference(_sessionStartTime!).inHours >= 2) {
      _activeCourt = null;
      _sessionStartTime = null;
    }
    return _activeCourt;
  }

  void setActiveCourt(Map<String, dynamic>? court) {
    _activeCourt = court;
    _sessionStartTime = court != null ? DateTime.now() : null;
    notifyListeners();
  }

  void clearSession() {
    _activeCourt = null;
    _sessionStartTime = null;
    notifyListeners();
  }

  bool get hasActiveSession => activeCourt != null;
}
