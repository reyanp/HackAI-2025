import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shinobi_self/core/theme/app_colors.dart';
import 'package:shinobi_self/core/theme/app_text_styles.dart';
import 'package:shinobi_self/models/character_path.dart';
import 'package:shinobi_self/models/mission.dart';
import 'package:shinobi_self/models/user_preferences.dart';
import 'package:shinobi_self/models/mood_entry.dart';
import 'package:shinobi_self/models/user_progress.dart';
import 'package:shinobi_self/features/achievements/achievements_screen.dart';
import 'package:shinobi_self/widgets/mission_completion_overlay.dart';
import 'package:shinobi_self/services/mission_generator_service.dart';
import 'package:shinobi_self/services/openai_service.dart';

// Provider for daily missions
final dailyMissionsProvider = StateNotifierProvider<DailyMissionsNotifier, AsyncValue<List<Mission>>>((ref) {
  return DailyMissionsNotifier(ref);
});

class DailyMissionsNotifier extends StateNotifier<AsyncValue<List<Mission>>> {
  final Ref _ref;

  DailyMissionsNotifier(this._ref) : super(const AsyncValue.loading()) {
    loadMissions();
  }

  Future<void> loadMissions() async {
    try {
      // Get user's character path
      final userPrefs = _ref.read(userPrefsProvider);
      if (userPrefs.characterPath == null) {
        state = const AsyncValue.data([]);
        return;
      }

      // Generate 3 AI missions
      state = const AsyncValue.loading();
      final missions = await MissionGeneratorService.generateInitialMissions(
        userPrefs.characterPath!,
        3, // Start with 3 missions
      );

      state = AsyncValue.data(missions);
    } catch (e) {
      print('Error loading AI missions: $e');
      // Fallback to empty list if there's an error
      state = const AsyncValue.data([]);
    }
  }

  void addMission(Mission mission) {
    state.whenData((missions) {
      state = AsyncValue.data([...missions, mission]);
    });
  }

  void updateMissions(List<Mission> newMissions) {
    state = AsyncValue.data(newMissions);
  }
}

// Provider for weekly missions
final weeklyMissionsProvider = StateProvider<List<Mission>>((ref) {
  final userPrefs = ref.watch(userPrefsProvider);
  if (userPrefs.characterPath != null) {
    return MissionData.getWeeklyMissions(userPrefs.characterPath!);
  }
  return [];
});

// Timer provider to check for mission resets
final missionTimerProvider = StreamProvider<void>((ref) {
  return Stream.periodic(const Duration(minutes: 1), (count) {
    final dailyMissionsAsync = ref.read(dailyMissionsProvider);
    final weeklyMissions = ref.read(weeklyMissionsProvider);
    
    // Check if any missions need to be reset
    bool needsWeeklyReset = weeklyMissions.any((m) => m.shouldReset);
    
    // Handle daily missions reset if needed
    dailyMissionsAsync.maybeWhen(
      data: (missions) {
        bool needsDailyReset = missions.any((m) => m.shouldReset);
        if (needsDailyReset) {
          final userPrefs = ref.read(userPrefsProvider);
          if (userPrefs.characterPath != null) {
            // Reload AI missions when reset is needed
            ref.read(dailyMissionsProvider.notifier).loadMissions();
          }
        }
      },
      orElse: () {}, // Do nothing for loading/error states
    );
    
    if (needsWeeklyReset) {
      final userPrefs = ref.read(userPrefsProvider);
      if (userPrefs.characterPath != null) {
        ref.read(weeklyMissionsProvider.notifier).state = 
          MissionData.getWeeklyMissions(userPrefs.characterPath!);
      }
    }
  });
});

// Provider for user XP
final userXpProvider = StateProvider<int>((ref) => 0);

// Provider for user streak
final userStreakProvider = StateProvider<int>((ref) => 0);

// Provider for selected mood
final selectedMoodProvider = StateProvider<String?>((ref) => null);

// Provider for daily mood submission status
final hasMoodSubmittedTodayProvider = StateProvider<bool>((ref) => false);

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the timer to trigger mission resets
    ref.watch(missionTimerProvider);
    
    final userPrefs = ref.watch(userPrefsProvider);
    final dailyMissions = ref.watch(dailyMissionsProvider);
    final weeklyMissions = ref.watch(weeklyMissionsProvider);
    final userXp = ref.watch(userXpProvider);
    final userStreak = ref.watch(userStreakProvider);
    
    // For demo purposes, set a default character path if none is selected
    if (userPrefs.characterPath == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(userPrefsProvider.notifier).state = userPrefs.copyWith(
          characterPath: CharacterPath.naruto,
          hasCompletedOnboarding: true,
        );
      });
      return const Center(child: CircularProgressIndicator());
    }
    
    final characterInfo = CharacterInfo.characters[userPrefs.characterPath]!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserHeader(context, characterInfo, userXp, userStreak),
          const SizedBox(height: 24),
          _buildDailyMissions(context, ref, dailyMissions),
          const SizedBox(height: 24),
          _buildWeeklyMissions(context, ref, weeklyMissions),
          const SizedBox(height: 24),
          _buildMoodTracker(context),
        ],
      ),
    );
  }
  
  Widget _buildUserHeader(
    BuildContext context, 
    CharacterInfo characterInfo, 
    int userXp, 
    int userStreak
  ) {
    final ninjaRank = _getNinjaRank(userXp);
    final nextRankXp = _getNextRankXp(userXp);
    final progress = userXp / nextRankXp;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _getPathColor(characterInfo.path).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      characterInfo.name[0],
                      style: AppTextStyles.heading1.copyWith(
                        color: _getPathColor(characterInfo.path),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${characterInfo.name} Path',
                        style: AppTextStyles.heading3.copyWith(
                          color: _getPathColor(characterInfo.path),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ninja Rank: $ninjaRank',
                        style: AppTextStyles.ninjaRank.copyWith(
                          color: _getRankColor(ninjaRank),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department, 
                          color: AppColors.narutoOrange,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$userStreak day streak',
                          style: AppTextStyles.streakCounter,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$userXp XP',
                      style: AppTextStyles.xpCounter,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress to ${_getNextRank(ninjaRank)}',
                      style: AppTextStyles.bodySmall,
                    ),
                    Text(
                      '$userXp / $nextRankXp XP',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(_getRankColor(ninjaRank)),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDailyMissions(
    BuildContext context, 
    WidgetRef ref, 
    AsyncValue<List<Mission>> missions
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Daily Missions',
              style: AppTextStyles.heading2,
            ),
            missions.when(
              data: (data) => _buildTimeUntilReset(data.firstOrNull?.resetTime),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Complete these missions to earn XP and level up',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 16),
        missions.when(
          data: (missionsList) {
            if (missionsList.isEmpty) {
              return const Center(child: Text('No missions available'));
            }
            return Column(
              children: missionsList
                  .map((mission) => _buildMissionCard(context, ref, mission))
                  .toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Error loading missions')),
        ),
        const SizedBox(height: 16),
        _buildGenerateAIMissionButton(context, ref),
      ],
    );
  }
  
  Widget _buildWeeklyMissions(
    BuildContext context, 
    WidgetRef ref, 
    List<Mission> missions
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Weekly Missions',
              style: AppTextStyles.heading2,
            ),
            _buildTimeUntilReset(missions.firstOrNull?.resetTime),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Bigger challenges for greater rewards',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (missions.isEmpty)
          const Center(child: CircularProgressIndicator())
        else
          ...missions.map((mission) => _buildMissionCard(context, ref, mission)).toList(),
      ],
    );
  }
  
  Widget _buildTimeUntilReset(DateTime? resetTime) {
    if (resetTime == null) return const SizedBox.shrink();
    
    final now = DateTime.now();
    final difference = resetTime.difference(now);
    
    String timeText;
    if (difference.inDays > 0) {
      timeText = '${difference.inDays}d ${difference.inHours % 24}h';
    } else if (difference.inHours > 0) {
      timeText = '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      timeText = '${difference.inMinutes % 60}m';
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 16),
        const SizedBox(width: 4),
        Text(
          'Resets in $timeText',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
  
  Widget _buildMissionCard(
    BuildContext context, 
    WidgetRef ref, 
    Mission mission
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mission.title,
                    style: mission.isCompleted
                        ? AppTextStyles.questTitle.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.textSecondary,
                          )
                        : AppTextStyles.questTitle,
                  ),
                ),
                Text(
                  '+${mission.xpReward} XP',
                  style: AppTextStyles.xpCounter,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mission.description,
              style: mission.isCompleted
                  ? AppTextStyles.questDescription.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: AppColors.textSecondary,
                    )
                  : AppTextStyles.questDescription,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mission.isCompleted
                    ? null
                    : () => _completeMission(context, ref, mission),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mission.isCompleted
                      ? AppColors.silverGray
                      : AppColors.chakraBlue,
                  disabledBackgroundColor: AppColors.silverGray,
                ),
                child: Text(
                  mission.isCompleted ? 'Completed' : 'Mark as Complete',
                  style: AppTextStyles.buttonMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMoodTracker(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final selectedMood = ref.watch(selectedMoodProvider);
        final hasMoodSubmittedToday = ref.watch(hasMoodSubmittedTodayProvider);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Mood Check-in',
              style: AppTextStyles.heading2,
            ),
            const SizedBox(height: 8),
            Text(
              hasMoodSubmittedToday 
                ? 'Thanks for checking in today!' 
                : 'How are you feeling today?',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMoodOption('😢', 'Sad', selectedMood, ref),
                        _buildMoodOption('😐', 'Okay', selectedMood, ref),
                        _buildMoodOption('🙂', 'Good', selectedMood, ref),
                        _buildMoodOption('😄', 'Great', selectedMood, ref),
                        _buildMoodOption('🤩', 'Amazing', selectedMood, ref),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: hasMoodSubmittedToday 
                          ? null 
                          : () => _submitMood(context, ref, selectedMood),
                        child: Text(
                          hasMoodSubmittedToday ? 'Submitted' : 'Submit Mood',
                          style: AppTextStyles.buttonMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildMoodOption(String emoji, String label, String? selectedMood, WidgetRef ref) {
    final isSelected = selectedMood == emoji;
    
    return GestureDetector(
      onTap: () {
        ref.read(selectedMoodProvider.notifier).state = emoji;
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.chakraBlue.withOpacity(0.2) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isSelected ? AppColors.chakraBlue : null,
              fontWeight: isSelected ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }

  void _submitMood(BuildContext context, WidgetRef ref, String? selectedMood) {
    if (selectedMood == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a mood first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Create new mood entry
    final moodType = MoodType.values.firstWhere(
      (type) => type.emoji == selectedMood,
      orElse: () => MoodType.okay,
    );
    
    final newEntry = MoodEntry(
      date: DateTime.now(),
      mood: moodType,
    );
    
    // Add to mood entries
    final currentEntries = ref.read(moodEntriesProvider);
    ref.read(moodEntriesProvider.notifier).state = [newEntry, ...currentEntries];

    // Update submission status
    ref.read(hasMoodSubmittedTodayProvider.notifier).state = true;

    // Update XP and progress
    final currentXp = ref.read(userXpProvider);
    final moodXpReward = 20; // XP reward for tracking mood
    final newXp = currentXp + moodXpReward;
    ref.read(userXpProvider.notifier).state = newXp;
    
    // Update user progress
    final currentProgress = ref.read(userProgressProvider);
    ref.read(userProgressProvider.notifier).state = currentProgress.copyWith(
      xp: newXp,
      level: _calculateLevel(newXp),
      rank: _calculateRank(newXp),
    );

    // Check achievements after updating progress
    ref.read(achievementsProvider.notifier).checkAchievements();

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mood submitted: ${moodType.label}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
      ),
    );
  }
  
  void _completeMission(BuildContext context, WidgetRef ref, Mission mission) {
    // Show mission completion overlay
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return MissionCompletionOverlay(
          missionTitle: mission.title,
          onSkip: () {
            // Just close the dialog and complete the mission
            Navigator.of(context).pop();
            _processMissionCompletion(context, ref, mission, 0); // No bonus XP
          },
          onSubmit: (imageFile, rating) {
            // Close the dialog and complete the mission with the image and rating
            Navigator.of(context).pop();
            
            // Add bonus XP if an image was uploaded
            int bonusXp = imageFile != null ? 10 : 0;
            
            _processMissionCompletion(context, ref, mission, bonusXp);
          },
        );
      },
    );
  }
  
  // Process the mission completion after the dialog is closed
  void _processMissionCompletion(BuildContext context, WidgetRef ref, Mission mission, int bonusXp) {
    // Update the mission to completed
    if (mission.frequency == MissionFrequency.daily) {
      // Get the current state of missions
      final dailyMissionsAsync = ref.read(dailyMissionsProvider);
      
      // Only update if we have data
      dailyMissionsAsync.maybeWhen(
        data: (missions) {
          final updatedMissions = missions.map((m) {
            if (m.id == mission.id) {
              return m.copyWith(
                isCompleted: true,
                completedAt: DateTime.now(),
              );
            }
            return m;
          }).toList();
          
          // Update missions list
          ref.read(dailyMissionsProvider.notifier).updateMissions(updatedMissions);
          
          // Check if all missions are completed to update streak
          final allCompleted = updatedMissions.every((m) => m.isCompleted);
          if (allCompleted) {
            final currentStreak = ref.read(userStreakProvider);
            ref.read(userStreakProvider.notifier).state = currentStreak + 1;
          }
        },
        orElse: () {
          // If there's no data, we can't update anything
          print('Cannot complete mission: No mission data available');
        },
      );
    } else {
      // Handle weekly missions (these use a simpler provider)
      final missions = ref.read(weeklyMissionsProvider);
      final updatedMissions = missions.map((m) {
        if (m.id == mission.id) {
          return m.copyWith(
            isCompleted: true,
            completedAt: DateTime.now(),
          );
        }
        return m;
      }).toList();
      
      // Update weekly missions list
      ref.read(weeklyMissionsProvider.notifier).state = updatedMissions;
    }
    
    // Update XP and progress - Include bonus XP if provided
    final currentXp = ref.read(userXpProvider);
    final newXp = currentXp + mission.xpReward + bonusXp;
    ref.read(userXpProvider.notifier).state = newXp;
    
    // Update user progress
    final currentProgress = ref.read(userProgressProvider);
    ref.read(userProgressProvider.notifier).state = currentProgress.copyWith(
      xp: newXp,
      level: _calculateLevel(newXp),
      rank: _calculateRank(newXp),
      completedMissions: currentProgress.completedMissions + 1,
      totalMissionsCompleted: currentProgress.totalMissionsCompleted + 1,
    );

    // Show bonus XP message if applicable
    if (bonusXp > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mission completed! +${mission.xpReward} XP + $bonusXp bonus XP'),
          backgroundColor: Colors.green,
        ),
      );
    }

    // Check achievements after updating progress
    ref.read(achievementsProvider.notifier).checkAchievements();
  }
  
  int _calculateLevel(int xp) {
    // Every 100 XP is a new level
    return (xp / 100).floor() + 1;
  }

  NinjaRank _calculateRank(int xp) {
    if (xp >= 2000) return NinjaRank.hokage;
    if (xp >= 1000) return NinjaRank.jounin;
    if (xp >= 500) return NinjaRank.chunin;
    return NinjaRank.genin;
  }
  
  String _getNinjaRank(int xp) {
    if (xp >= 2000) return 'Hokage';
    if (xp >= 1000) return 'Jounin';
    if (xp >= 500) return 'Chunin';
    return 'Genin';
  }
  
  String _getNextRank(String currentRank) {
    switch (currentRank) {
      case 'Genin': return 'Chunin';
      case 'Chunin': return 'Jounin';
      case 'Jounin': return 'Hokage';
      default: return 'Hokage';
    }
  }
  
  int _getNextRankXp(int currentXp) {
    if (currentXp < 500) return 500;
    if (currentXp < 1000) return 1000;
    if (currentXp < 2000) return 2000;
    return 3000; // Beyond Hokage
  }
  
  Color _getPathColor(CharacterPath path) {
    switch (path) {
      case CharacterPath.naruto:
        return AppColors.narutoPathColor;
      case CharacterPath.sasuke:
        return AppColors.sasukePathColor;
      case CharacterPath.sakura:
        return AppColors.sakuraPathColor;
    }
  }
  
  Color _getRankColor(String rank) {
    switch (rank) {
      case 'Genin': return AppColors.geninColor;
      case 'Chunin': return AppColors.chuninColor;
      case 'Jounin': return AppColors.jouninColor;
      case 'Hokage': return AppColors.hokageColor;
      default: return AppColors.chakraBlue;
    }
  }
  
  Widget _buildGenerateAIMissionButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.smart_toy),
      label: const Text('Generate AI Mission'),
      onPressed: () => _generateAIMission(context, ref),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
  
  Future<void> _generateAIMission(BuildContext context, WidgetRef ref) async {
    // Check if API key is set in config
    final apiKey = OpenAIService.getApiKey();
    if (apiKey.isEmpty || apiKey == 'YOUR_OPENAI_API_KEY') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add your OpenAI API key in lib/config/api_keys.dart'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating your personalized mission...'),
          ],
        ),
      ),
    );
    
    try {
      // Get user's character path
      final userPrefs = ref.read(userPrefsProvider);
      if (userPrefs.characterPath == null) {
        Navigator.pop(context); // Close loading dialog
        return;
      }
      
      // Generate AI mission
      final mission = await MissionGeneratorService.generateAIMission(userPrefs.characterPath!);
      
      // Close loading dialog
      Navigator.pop(context);
      
      if (mission == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to generate mission. Please try again later.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Add mission to daily missions
      ref.read(dailyMissionsProvider.notifier).addMission(mission);
      
      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New mission generated: ${mission.title}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still showing
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
