import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'blocs/plant_cubit.dart';
import 'blocs/profile_cubit.dart';
import 'blocs/solution_cubit.dart';
import 'blocs/subscription_cubit.dart';
import 'blocs/track_cubit.dart';
import 'config.dart';
import 'screens/map_screen.dart';
import 'services/elevation_service.dart';
import 'services/plant_classifier.dart';
import 'services/plant_reranker.dart';
import 'services/plant_service.dart';
import 'services/profile_service.dart';
import 'services/subscription_service.dart';
import 'services/track_detector.dart';
import 'services/track_service.dart';
import 'services/weather_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Hive
  await Hive.initFlutter();

  // Init Mobile Ads SDK
  await MobileAds.instance.initialize();

  // Init subscription service
  final subscriptionService = SubscriptionService();
  await subscriptionService.init();

  // Init Mapbox access token
  MapboxOptions.setAccessToken(AppConfig.mapboxPublicToken);

  runApp(MonyxApp(subscriptionService: subscriptionService));
}

class MonyxApp extends StatelessWidget {
  final SubscriptionService subscriptionService;
  const MonyxApp({super.key, required this.subscriptionService});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ProfileCubit(ProfileService())..load()),
        BlocProvider(
          create: (_) => SolutionCubit(
            weatherService: WeatherService(),
            elevationService: ElevationService(),
          ),
        ),
        BlocProvider(
          create: (_) => SubscriptionCubit(subscriptionService)..load(),
        ),
        BlocProvider(
          create: (_) =>
              TrackCubit(detector: TrackDetector(), service: TrackService()),
        ),
        BlocProvider(
          create: (_) => PlantCubit(
            classifier: PlantClassifier(),
            service: PlantService(),
            reranker: PlantReranker(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Monyx',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orangeAccent,
            brightness: Brightness.dark,
          ),
        ),
        home: const MapScreen(),
      ),
    );
  }
}
