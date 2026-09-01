import 'package:flutter/material.dart';

class ParaSafetyLanding {
  ParaSafetyLanding._();

  static Future<void> show(BuildContext context) async {
    final hour = DateTime.now().hour;
    final isNight = hour >= 22 || hour < 5;
    final slides = <_SafetySlide>[];

    if (isNight) {
      slides.addAll([
        const _SafetySlide(
          icon: Icons.nightlight_round,
          iconColor: Color(0xFFFF9800),
          iconBackgroundColor: Color(0xFFFFF3E0),
          title: 'Night Travel Warning',
          description:
              'Walking at night is extremely dangerous. Stay alert, stick to well-lit areas, and avoid isolated streets.',
        ),
        const _SafetySlide(
          icon: Icons.schedule,
          iconColor: Color(0xFFE65100),
          iconBackgroundColor: Color(0xFFFBE9E7),
          title: 'Limited PUVs Available',
          description:
              'Public vehicles are very limited at this hour. Expect longer waits and fewer route options. Plan your trip carefully.',
        ),
        const _SafetySlide(
          icon: Icons.share_location,
          iconColor: Color(0xFF1565C0),
          iconBackgroundColor: Color(0xFFE3F2FD),
          title: 'Notify Someone',
          description:
              'Share your whereabouts with a trusted contact in case of emergency. Use the share location feature in the Commute tab.',
        ),
      ]);
    }

    slides.add(
      const _SafetySlide(
        icon: Icons.warning_amber_rounded,
        iconColor: Color(0xFF1A73E8),
        iconBackgroundColor: Color(0xFFE8F0FE),
        title: 'Stay Aware of Your Surroundings',
        description:
            'Avoid using your phone while walking near roads and train tracks. Stay alert - your safety comes first.',
      ),
    );

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SafetyDialog(slides: slides, isNight: isNight),
    );
  }
}

class _SafetySlide {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String description;

  const _SafetySlide({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.description,
  });
}

class _SafetyDialog extends StatefulWidget {
  final List<_SafetySlide> slides;
  final bool isNight;

  const _SafetyDialog({required this.slides, required this.isNight});

  @override
  State<_SafetyDialog> createState() => _SafetyDialogState();
}

class _SafetyDialogState extends State<_SafetyDialog> {
  late final PageController _pageController;
  int _currentPage = 0;

  bool get _isLastPage => _currentPage == widget.slides.length - 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _continue() {
    if (_isLastPage) {
      Navigator.of(context).pop();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isNight
        ? const Color(0xFF1A1A2E)
        : Colors.white;

    return Dialog.fullscreen(
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.slides.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, index) => _buildSlide(
                  widget.slides[index],
                ),
              ),
            ),
            if (widget.slides.length > 1) _buildPageIndicator(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isNight
                        ? const Color(0xFFFF9800)
                        : const Color(0xFF1D6FD8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLastPage ? 'Got it' : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.slides.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? (widget.isNight
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF1D6FD8))
                : (widget.isNight ? Colors.white24 : const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildSlide(_SafetySlide slide) {
    final titleColor = widget.isNight ? Colors.white : const Color(0xFF1A1A1A);
    final descriptionColor = widget.isNight
        ? Colors.white70
        : const Color(0xFF757575);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: widget.isNight
                  ? slide.iconColor.withValues(alpha: 0.15)
                  : slide.iconBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 48, color: slide.iconColor),
          ),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: titleColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: descriptionColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
