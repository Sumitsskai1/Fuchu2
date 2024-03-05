//
//  AppDelegate.swift
//  TaskManager
//
//  Created by SuMiTS&S Development Team 1 on 2023/12/08.
//

import Combine
import Foundation
import SwiftUI
import UserNotifications
// カラーテーマ
let appThemeColor = Color.blue

// サブタスクモデル
struct Subtask: Identifiable, Codable {
    var id = UUID()
    var title: String
    var deadline: Date?
    var memo: String? // 新しいメモ項目
}

// タスクモデル
struct Task: Identifiable, Codable {
    var id = UUID()
    var title: String
    var subtasks: [Subtask]
}
// アプリのメインエントリーポイント
@main
struct TaskManagerApp: App {
    @StateObject private var taskManager = TaskManager()

    var body: some Scene {
        WindowGroup {
            TaskListView()
                .environmentObject(taskManager)
                .onAppear {
                    // アプリの起動時に通知の許可をリクエストする
                    requestNotificationAuthorization()
                }
        }
    }
    }
    
    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting authorization for notifications: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // エラーメッセージを表示するアラートを表示
                    let alertController = UIAlertController(title: "通知の許可が必要です", message: "タスクの期限を管理するために通知の許可が必要です。設定から通知を有効にしてください。", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "設定を開く", style: .default) { _ in
                        // アプリの設定画面を開く
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    })
                    alertController.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
                    
                    // 適切なウィンドウシーンを取得してアラートを表示
                    if let window = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive })?.windows
                        .first(where: { $0.isKeyWindow }) {
                        window.rootViewController?.present(alertController, animated: true)
                    }
                }
            }
            // 許可が得られなかった場合の処理を追加することもできます
        }
    }

// タスク管理クラス
class TaskManager: ObservableObject {
    @Published var tasks: [Task] = []
    
    private let tasksKey = "tasks"
    
    init() {
        // UserDefaultsから保存されたタスクを読み込む
        if let storedTasks = UserDefaults.standard.data(forKey: tasksKey) {
            let decoder = JSONDecoder()
            if let decodedTasks = try? decoder.decode([Task].self, from: storedTasks) {
                tasks = decodedTasks
                validateTasks() // タスクの整合性を検証
            }
        }
    }
 
    // タスクの整合性を検証する
    func validateTasks() {
        for task in tasks {
            for subtask in task.subtasks {
                guard tasks.contains(where: { $0.subtasks.contains(where: { $0.id == subtask.id }) }) else {
                    print("Inconsistency found: Task \(task.title) and Subtask \(subtask.title) are not properly related.")
                    DispatchQueue.main.async {
                        // 不整合をハンドリングするコードをここに追加（例：アラートの表示）
                    }
                    break
                }

                // 期限が過ぎている場合に通知を送信する
                if let deadline = subtask.deadline, Date() >= deadline {
                    let notificationContent = UNMutableNotificationContent()
                    notificationContent.title = "サブタスクの期限が過ぎています"
                    notificationContent.body = "\(subtask.title)の期限が過ぎています。"

                    let notificationTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    let notificationRequest = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: notificationTrigger)

                    UNUserNotificationCenter.current().add(notificationRequest) { error in
                        if let error = error {
                            print("Error adding notification request: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    
    // タスクを保存する
    func saveTasks() {
        let encoder = JSONEncoder()
        if let encodedTasks = try? encoder.encode(tasks) {
            UserDefaults.standard.set(encodedTasks, forKey: tasksKey)
        }
    }
    
    // サブタスクを削除する
    func deleteSubtask(task: Task, subtask: Subtask) {
        if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
           let subtaskIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtask.id }) {
            tasks[taskIndex].subtasks.remove(at: subtaskIndex)

            // タスクが空になった場合、タスクも削除
            if tasks[taskIndex].subtasks.isEmpty {
                tasks.remove(at: taskIndex)
            }

            saveTasks()
        }
    }
}

// サブタスク行のビュー
struct SubtaskRow: View {
    var subtask: Subtask
    var onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(subtask.title)
            Spacer()
            if let memo = subtask.memo, !memo.isEmpty {
                Text("📝") // メモがある場合にアイコンなどを表示
            }
            if let deadline = subtask.deadline {
                Text("\(deadline, formatter: dateFormatter)")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: { onDelete() }) {
                Text("Delete")
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// タスク行のビュー
struct TaskRow: View {
    var task: Task
    var onDeleteSubtask: (Task, Subtask) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(task.title)
                .font(.headline)

            ForEach(task.subtasks) { subtask in
                SubtaskRow(subtask: subtask) {
                    onDeleteSubtask(task, subtask)
                }
            }
        }
    }
}

// タスクリストビュー
struct TaskListView: View {
    @EnvironmentObject var taskManager: TaskManager
    @State private var isAddingTask = false
    @State private var selectedSubtask: Subtask?

    var body: some View {
        NavigationView {
            List {
                ForEach(taskManager.tasks) { task in
                    Section(header: Text(task.title).font(.headline)) {
                        ForEach(task.subtasks) { subtask in
                            SubtaskRow(subtask: subtask) {
                                taskManager.deleteSubtask(task: task, subtask: subtask)
                            }
                            .onTapGesture {
                                selectedSubtask = subtask
                            }
                        }
                    }
                }
                .onDelete(perform: deleteTask) // タスクの削除機能を追加
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("タスク管理", displayMode: .inline)
            .navigationBarItems(
                trailing:
                    Button(action: {
                        isAddingTask = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                    }.foregroundColor(appThemeColor)
            )
            .sheet(isPresented: $isAddingTask) {
                AddTaskView(isPresented: $isAddingTask)
                    .environmentObject(taskManager)
            }
            .fullScreenCover(item: $selectedSubtask) { subtask in
                if let taskWithSubtask = taskManager.tasks.first(where: { $0.subtasks.contains { $0.id == subtask.id } }) {
                    SubtaskDetail(taskName: taskWithSubtask.title,
                                  subtaskName: subtask.title,
                                  deadline: subtask.deadline,
                                  memo: subtask.memo)
                        .environmentObject(taskManager)
                } else {
                    EmptyView()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // タスクを削除する
    private func deleteTask(offsets: IndexSet) {
        taskManager.tasks.remove(atOffsets: offsets)
        taskManager.saveTasks()
    }
}

// タスク追加ビュー
struct AddTaskView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var taskManager: TaskManager

    @State private var selectedTaskIndex: Int = -1
    @State private var isNewTaskSelected: Bool = true
    @State private var newTaskTitle = ""
    @State private var newSubtaskTitle = ""
    @State private var selectedDate = Date()
    @State private var newSubtaskMemo = ""
    @State private var notificationTimeIndex = 0 // 通知時間の選択肢のインデックス
    let notificationTimeOptions = ["5 minutes before", "10 minutes before", "15 minutes before","30 minutes before","1 hours before","2 hours before","3 hourss before","6 hours before"] // 適切な選択肢を定義する
    let notificationTimes = [5, 10, 15, 30, 60, 120, 180 , 360] //分単位で通知を受け取る時間を定義する
    var body: some View {
        NavigationView {
            Form {
                Picker("Select Task", selection: $selectedTaskIndex) {
                    ForEach(0..<taskManager.tasks.count, id: \.self) { index in
                        Text(taskManager.tasks[index].title).tag(index)
                    }
                    Text("New Task").tag(-1)
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 80) // ピッカーの高さを調整
                .onChange(of: selectedTaskIndex) { newIndex in
                    isNewTaskSelected = newIndex == -1
                    if !isNewTaskSelected {
                        selectedDate = Date()
                        newSubtaskMemo = ""
                    }
                }
                if isNewTaskSelected {
                    Section(header: Text("New Task")) {
                        TextField("タスク名", text: $newTaskTitle)
                    }
                }
                Section(header: Text("New Subtask")) {
                    TextField("サブタスク名", text: $newSubtaskTitle)
                    DatePicker("期限", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("メモ", text: $newSubtaskMemo)
                    Picker("リマインダー", selection: $notificationTimeIndex) {
                        ForEach(notificationTimeOptions.indices, id: \.self) { index in
                            Text(notificationTimeOptions[index]).tag(index)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
            }
            .navigationBarTitle("タスク追加", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                isPresented = false
            }, trailing:   Button(action: {
                if isNewTaskSelected {
                    let newSubtask = Subtask(title: newSubtaskTitle, deadline: selectedDate, memo: newSubtaskMemo)
                    let newTask = Task(title: newTaskTitle, subtasks: [newSubtask])
                    taskManager.tasks.append(newTask)

                    // 通知を設定する
                    let notificationContent = UNMutableNotificationContent()
                    notificationContent.title = "サブタスクの期限が近づいています"
                    notificationContent.body = "\(newSubtask.title)の期限が近づいています。"

                    // 通知のトリガーを設定する
                    let notificationTriggerDate = Calendar.current.date(byAdding: .minute, value: -notificationTimes[notificationTimeIndex], to: selectedDate)!
                    let notificationTrigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTriggerDate), repeats: false)

                    // 通知リクエストを作成して追加する
                    let notificationRequest = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: notificationTrigger)
                    UNUserNotificationCenter.current().add(notificationRequest) { error in
                        if let error = error {
                            print("Error adding notification request: \(error.localizedDescription)")
                        }
                    }
                } else {
                    let newSubtask = Subtask(title: newSubtaskTitle, deadline: selectedDate, memo: newSubtaskMemo)
                    taskManager.tasks[selectedTaskIndex].subtasks.append(newSubtask)

                    // 通知を設定する
                    let notificationContent = UNMutableNotificationContent()
                    notificationContent.title = "サブタスクの期限が近づいています"
                    notificationContent.body = "\(newSubtask.title)の期限が近づいています。"

                    // 通知のトリガーを設定する
                    let notificationTriggerDate = Calendar.current.date(byAdding: .minute, value: -notificationTimes[notificationTimeIndex], to: selectedDate)!
                    let notificationTrigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTriggerDate), repeats: false)

                    // 通知リクエストを作成して追加する
                    let notificationRequest = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: notificationTrigger)
                    UNUserNotificationCenter.current().add(notificationRequest) { error in
                        if let error = error {
                            print("Error adding notification request: \(error.localizedDescription)")
                        }
                    }
                }
                taskManager.saveTasks()
                isPresented = false
            }) {
                Text("Add")
            })

            .onAppear {
                               if taskManager.tasks.isEmpty {
                    isNewTaskSelected = true
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// View拡張
extension View {
    func maxLength(_ maxLength: Int) -> some View {
        return modifier(MaxLengthModifier(maxLength: maxLength))
    }
}

// 文字数制限修飾子
struct MaxLengthModifier: ViewModifier {
    let maxLength: Int

    func body(content: Content) -> some View {
        content
        // .onReceive(Just(content)) {
        // newValue in
        //   let value = newValue as! Text
        //   if value.wrappedValue.count > maxLength {
        //       value.wrappedValue = String(value.wrappedValue.prefix(maxLength))
        //   }
        //  }
    }
}



struct SubtaskDetail: View {
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.presentationMode) var presentationMode

    var taskName: String
    var subtaskName: String
    var deadline: Date?
    var memo: String?
    @State private var editedMemo: String // 編集用のメモを追加
    @State private var editedSubtaskName: String // 編集用のサブタスク名を追加

    init(taskName: String, subtaskName: String, deadline: Date?, memo: String?) {
        self.taskName = taskName
        self.subtaskName = subtaskName
        self.deadline = deadline
        _editedMemo = State(initialValue: memo ?? "") // メモの初期値を設定
        _editedSubtaskName = State(initialValue: subtaskName) // サブタスク名の初期値を設定
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("タスク詳細")
                    .font(.headline)
                    .foregroundColor(.blue)) {
                    HStack {
                        Text("タスク名")
                        Spacer()
                        Text(taskName)
                    }
                    HStack {
                        Text("サブタスク名")
                        Spacer()
                        TextField("サブタスク名", text: $editedSubtaskName).multilineTextAlignment(.trailing)
                    }
                    if let deadline = deadline {
                        HStack {
                            Text("期限")
                            Spacer()
                            Text("\(deadline, formatter: dateFormatter)")
                        }
                    }
                }
                Section(header: Text("メモ📝")
                    .font(.headline)
                    .foregroundColor(.blue)) {
                    TextEditor(text: $editedMemo)
                        .frame(height: 100)
                }
            }
            .navigationBarTitle("サブタスク詳細", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                },
                trailing: Button(action: {
                    // 編集されたメモを保存する
                    if let taskIndex = taskManager.tasks.firstIndex(where: { $0.subtasks.contains { $0.title == subtaskName } }),
                       let subtaskIndex = taskManager.tasks[taskIndex].subtasks.firstIndex(where: { $0.title == subtaskName }) {
                        taskManager.tasks[taskIndex].subtasks[subtaskIndex].memo = editedMemo
                        taskManager.tasks[taskIndex].subtasks[subtaskIndex].title = editedSubtaskName // 編集されたサブタスク名を保存
                        taskManager.saveTasks()
                    }
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save")
                }
            )
            .padding()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}


