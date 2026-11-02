
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartAIStudio());
}

class SmartAIStudio extends StatelessWidget {
  const SmartAIStudio({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'کارگاه هوشمند',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xff42c9a5),
        scaffoldBackgroundColor: const Color(0xff0b1020),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}

class AIMessage {
  final String role;
  final String content;

  AIMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
  };

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      json['role'] ?? 'assistant',
      json['content'] ?? '',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final storage = const FlutterSecureStorage();
  final controller = TextEditingController();
  final scrollController = ScrollController();

  final List<AIMessage> messages = [];
  final List<PlatformFile> attachments = [];

  String endpoint = 'https://api.openai.com/v1/chat/completions';
  String model = 'gpt-4o-mini';
  String apiKey = '';

  bool loading = false;
  int selectedTab = 0;

  final List<String> providers = [
    'OpenAI',
    'Google Gemini',
    'Anthropic Claude',
    'API اختصاصی'
  ];

  @override
  void initState() {
    super.initState();
    loadSettings();
    loadHistory();
  }

  Future<void> loadSettings() async {
    final savedEndpoint = await storage.read(key: 'endpoint');
    final savedModel = await storage.read(key: 'model');
    final savedKey = await storage.read(key: 'apiKey');

    if (!mounted) return;

    setState(() {
      endpoint = savedEndpoint ?? endpoint;
      model = savedModel ?? model;
      apiKey = savedKey ?? '';
    });
  }

  Future<void> saveSettings(
    String newEndpoint,
    String newModel,
    String newKey,
  ) async {
    await storage.write(key: 'endpoint', value: newEndpoint);
    await storage.write(key: 'model', value: newModel);
    await storage.write(key: 'apiKey', value: newKey);

    if (!mounted) return;

    setState(() {
      endpoint = newEndpoint;
      model = newModel;
      apiKey = newKey;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تنظیمات ذخیره شد')),
    );
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('chat_history');

    if (data == null) return;

    try {
      final decoded = jsonDecode(data) as List;

      if (!mounted) return;

      setState(() {
        messages.addAll(
          decoded.map(
            (item) => AIMessage.fromJson(item),
          ),
        );
      });
    } catch (_) {
      // تاریخچه نامعتبر نادیده گرفته می‌شود.
    }
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'chat_history',
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (result == null) return;

    setState(() {
      attachments.addAll(result.files);
    });
  }

  Future<String> readAttachment(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) return '';

    final ext = file.extension?.toLowerCase() ?? '';

    const textExtensions = {
      'txt', 'md', 'html', 'htm', 'css', 'js',
      'json', 'xml', 'dart', 'py', 'java',
      'kt', 'cpp', 'c', 'h', 'sql', 'csv',
      'yaml', 'yml', 'php', 'log'
    };

    if (textExtensions.contains(ext)) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    return 'محتوای فایل ${file.name} به صورت مستقیم '
        'قابل استخراج نیست. نوع فایل: $ext';
  }

  Future<void> sendMessage() async {
    final question = controller.text.trim();

    if (question.isEmpty && attachments.isEmpty) return;

    if (apiKey.isEmpty || endpoint.isEmpty || model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ابتدا تنظیمات هوش مصنوعی را کامل کن'),
        ),
      );
      openSettings();
      return;
    }

    final fileParts = <String>[];

    for (final file in attachments) {
      final content = await readAttachment(file);

      fileParts.add(
        '\n\n--- فایل: ${file.name} ---\n$content',
      );
    }

    final fullQuestion = question + fileParts.join();

    setState(() {
      messages.add(AIMessage('user', fullQuestion));
      controller.clear();
      attachments.clear();
      loading = true;
    });

    await saveHistory();
    scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages.map((m) => m.toJson()).toList(),
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(minutes: 3));

      final data = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw Exception(
          data['error']?['message'] ??
          'خطای ارتباط با سرویس: ${response.statusCode}',
        );
      }

      final answer =
          data['choices']?[0]?['message']?['content'];

      if (answer == null) {
        throw Exception('پاسخ معتبر دریافت نشد');
      }

      final answerText = answer is String
          ? answer
          : answer.toString();

      if (!mounted) return;

      setState(() {
        messages.add(
          AIMessage('assistant', answerText),
        );
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        messages.add(
          AIMessage(
            'assistant',
            'خطا در ارتباط:\n$e',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
        await saveHistory();
        scrollToBottom();
      }
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void newChat() {
    setState(() {
      messages.clear();
    });
    saveHistory();
  }

  void openSettings() {
    final endpointController =
        TextEditingController(text: endpoint);
    final modelController =
        TextEditingController(text: model);
    final keyController =
        TextEditingController(text: apiKey);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff18233b),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تنظیمات هوش مصنوعی',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: endpointController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'آدرس API',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'نام مدل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'کلید API',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  await saveSettings(
                    endpointController.text.trim(),
                    modelController.text.trim(),
                    keyController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('ذخیره تنظیمات'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildMessage(AIMessage message) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xff21466a)
              : const Color(0xff18233b),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'شما' : 'هوش مصنوعی',
              style: const TextStyle(
                color: Color(0xff65d6b0),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: message.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: Colors.white,
                  height: 1.7,
                ),
                code: const TextStyle(
                  color: Color(0xff65d6b0),
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xff080e1b),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget chatScreen() {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 70,
                          color: Color(0xff65d6b0),
                        ),
                        SizedBox(height: 15),
                        Text(
                          'به کارگاه هوشمند خوش آمدی',
                          style: TextStyle(fontSize: 21),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'ایده نرم‌افزارت را بنویس و ساخت آن را شروع کن.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  itemBuilder: (_, index) =>
                      buildMessage(messages[index]),
                ),
        ),
        if (loading)
          const LinearProgressIndicator(),
        if (attachments.isNotEmpty)
          SizedBox(
            height: 55,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: attachments.map((f) {
                return Chip(
                  label: Text(f.name),
                  onDeleted: () {
                    setState(() => attachments.remove(f));
                  },
                );
              }).toList(),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                IconButton(
                  onPressed: pickFiles,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'افزودن فایل',
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'درخواست خود را بنویس...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton.filled(
                  onPressed: loading ? null : sendMessage,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget projectsScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 65),
            const SizedBox(height: 15),
            const Text(
              'مدیریت پروژه‌ها',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 10),
            const Text(
              'مدیریت فایل‌های چندگانه، ویرایشگر پروژه '
              'و خروجی ZIP در مرحله بعد تکمیل می‌شوند.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: pickFiles,
              icon: const Icon(Icons.upload_file),
              label: const Text('انتخاب فایل'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'کارگاه هوشمند',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: newChat,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'گفتگوی جدید',
          ),
          IconButton(
            onPressed: openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'تنظیمات',
          ),
        ],
      ),
      body: selectedTab == 0
          ? chatScreen()
          : projectsScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            label: 'دستیار هوشمند',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: 'پروژه‌ها',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
