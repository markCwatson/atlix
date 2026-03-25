// main.dart is purely wiring. It connects services to cubits, cubits to the
// ... widget tree, and sets the home screen.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'blocs/hike_track_cubit.dart';
import 'blocs/plant_cubit.dart';
import 'blocs/profile_cubit.dart';
import 'blocs/solution_cubit.dart';
import 'blocs/subscription_cubit.dart';
import 'blocs/track_cubit.dart';
import 'config.dart';
import 'screens/map_screen.dart';
import 'services/elevation_service.dart';
import 'services/hike_track_service.dart';
import 'services/plant_classifier.dart';
import 'services/plant_reranker.dart';
import 'services/plant_service.dart';
import 'services/profile_service.dart';
import 'services/subscription_service.dart';
import 'services/track_detector.dart';
import 'services/track_service.dart';
import 'services/weather_service.dart';

void main() async {
  // required whenever you call native platform code before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Initialization order matters. Hive first (other services may need it),
  //... then ads, then subscriptions, then Mapbox token
  await Hive.initFlutter();
  await MobileAds.instance.initialize();

  // The subscription service is created outside the widget tree and passed in
  //... this is because it needs to start listening to the App Store's purchase
  //... stream immediately, before any UI exists.
  final subscriptionService = SubscriptionService();
  await subscriptionService.init();

  MapboxOptions.setAccessToken(AppConfig.mapboxPublicToken);

  runApp(MonyxApp(subscriptionService: subscriptionService));
}

class MonyxApp extends StatelessWidget {
  final SubscriptionService subscriptionService;
  const MonyxApp({super.key, required this.subscriptionService});

  @override
  Widget build(BuildContext context) {
    // every screen in the app can access any of these cubits.
    // Manual DI (no framework) — Each cubit receives its services as
    //... constructor arguments. No GetIt, no Riverpod, no service locator.
    return MultiBlocProvider(
      providers: [
        // note: Each cubit is created lazily (only when first accessed)
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
        BlocProvider(
          create: (_) => HikeTrackCubit(service: HikeTrackService()),
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
