//
//  BlasterState.swift
//  blaster
//
//  Created by MARK LUCOVSKY on 1/17/25.
//

import SwiftUI
import AVFoundation

class BlasterState: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @ObservedObject var generalSettings: GeneralSettings = GeneralSettings()
  
  @Published var availableTiles: [TileModel] = []
  @Published var pages: [PageModel] = []
  @Published var filteredTiles: [PageTileModel] = []
  @Published var selectedTiles: [TileModel] = []
  @Published var generatedText: String = ""
  @Published var generatedAudio: String = ""
  @Published var thinking: Bool = false
  @Published var waiting: Bool = false

  @Published var cache: BlasterCacheModel = BlasterCacheModel()
    
  private var openAIClient: OpenAISwift?
  private var maxSelected = 4
  private var apiTimer = ApiTimer()
  private var audioPlayer: AVAudioPlayer? = nil
  
  func setTiles(tiles: [TileModel]) {
    availableTiles = tiles
  }
  
  func setPages(pages: [PageModel]) {
    self.pages = pages
  }
  
  func toggleSelection(for tile: TileModel) {
    
    func triggerUpdate(tiles: [TileModel]) -> Void {
      print("tu: \(tiles.count)")
      self.waiting = true
      apiTimer.setAlarm(after: 1) {
        DispatchQueue.main.async {
          self.waiting = false
          self.generateText(tiles: tiles)
        }
      }
    }
    
    if selectedTiles.contains(tile) {
      
      // remove selection
      selectedTiles.removeAll { $0 == tile }
      
      // recalc the remaining phrase
      if selectedTiles.count > 1 {
        triggerUpdate(tiles: selectedTiles)
      } else if selectedTiles.count == 1 {
        if generalSettings.autoVoiceOnSingleWord {
          print("todo -- generate voice for single word commands")
        }
        self.generatedText = selectedTiles.first!.displayName
      }
      
    } else if selectedTiles.count < maxSelected {
      // changing state to selected
      tile.recordMetric(metric: .selected)
      selectedTiles.append(tile)
      
      if selectedTiles.count == 1 {
        if generalSettings.autoVoiceOnSingleWord {
          print("todo -- generate voice for single word commands")
        }
        self.generatedText = tile.displayName
      } else {
        triggerUpdate(tiles: selectedTiles)
        //.padding(24)
      }
    }
  }
  
  func resetSelectedTiles() -> Void {
    selectedTiles.removeAll()
    self.generatedText = ""
    self.generatedAudio = ""
  }
  
  @Published var pageFilters: Set<String> = [TilePage.home.rawValue]
  func setPageFilters(filters: Set<String>) {
    // disallow .all and mostused comingled
    self.pageFilters = filters
    applyPageFilter()
  }
  
  // Filter logic
  func applyPageFilter() {
    
    // strip and special case the fake page filters:
    // all, mostused
    if self.pageFilters == [TilePage.all.rawValue] {
      filteredTiles = []//availableTiles
    //} else if self.pageFilters == [TilePage.home.rawValue] {
      //filteredTiles = availableTiles
    } else if self.pageFilters == [TilePage.mostused.rawValue] {
      //filteredTiles = availableTiles.sorted(by: {$0.metrics[.selected]!.count > $1.metrics[.selected]!.count})
      
    } else {
      // find the page that matches this filter
      if let page  = pages.first{self.pageFilters.contains($0.displayName)} {
        filteredTiles = page.orderedTiles.map{
          $0//.tile
        }
      } else {
        //filteredTiles = availableTiles.filter{ self.pageFilters.isSubset(of: $0.pages)}
      }
    }
  }
  
  
  
  
  
  
  private func joinSelection() -> String {
      return self.selectedTiles.map {
          $0.wordClass.isEmpty ? $0.value : "\($0.value) (\($0.wordClass))"
      }
      .joined(separator: ", ")
  }

  
  // phrase and sentence
  // 
  
  
  func generateText(tiles: [TileModel]) {
    var model: OpenAIModelType = .other(Config.model)
    var modalities: [String]? = nil
    var audio: [String: String]? = nil
    
    print("gt: \(tiles.count)")
    
    // record the
    if generalSettings.integrateVoice {
      model = .other("gpt-4o-audio-preview")
      modalities = ["text", "audio"]
      audio = ["voice": "nova", "format": "mp3"]
    }
   
    if self.generalSettings.useCache {
      // if there is data in the cache, use it
      if let hit = self.cache.lookup(tiles: tiles) {
        self.generatedText = hit.text
        self.generatedAudio = hit.audio
        self.playAudio(fromBase64: hit.audio)
        print("from cache: \(hit.key)")
        return
      }
    }
    
    tiles.forEach { tile in
      tile.recordMetric(metric: .used)
    }
    self.thinking = true
    
    let systemPrompt: [ChatMessage] = [
      ChatMessage(role: .system, content: "Your user has a disability that leaves them non verbal. You are their voice and soul. You are responsible for communication on their behalf."),
      ChatMessage(role: .system, content: "Users have a small vocabulary of words and phrases, they communicate with you using these items selected from their touch screen phone or device. Your job is to communicate your user's intent using full sentances to one or more folks that do not have any communication disabilities."),
      ChatMessage(role: .system, content: "Never generate anything that might be viewed as refering to sex acts, sound pornographic, or violent. For instance if the two words are make and love, do not generate a sentace like, I want to feel good, lets make love."),
      ChatMessage(role: .system, content: "Users often intend to communicate with a question that relates to themselves. E.g., when presented with the items: mom, tired -- the generated response should be something like: 'Mom, I am tired. Can I go lie down' or 'Mom, are you tired? I am, Lets go lie down and take a nap.'"),
      ChatMessage(role: .system, content: "Words can either be a comman seperated list of words, or a comma seperated list of words with a word class annotation in parens, after the word. The annotion should be used by you to provide context on how the word should be used. For instance the word 'snack bar' can be a place where a person goes to eat something. The word can also mean a type of food, like a granola bar, a protein bar, etc. An annotation of (place) would imply the first case, while an annotation of (food) would imply the second case. When faced with a word list of 'mom, snack bar (food)', you should never generate a sentence that includes going to a snack bar. In this case, since it's annotation is 'food', the snack bar is something you eat, not a place you go to.'"),
      ChatMessage(role: .system, content: "Your user has the grammar and vocabulary of a 1st grade student, 6 years old. This is the voice you should communicate in")
    ]
    
    let userPrompt = [ChatMessage(role: .user, content: joinSelection())]
    
    openAIClient?.sendChat(
      with: systemPrompt + userPrompt,
      model: model,
      modalities: modalities,
      audio: audio,
      temperature: 0.7,
      maxTokens: generalSettings.integrateVoice ? 10000 : 500
    ) { result in
      DispatchQueue.main.async {
        self.thinking = false
        switch result {
        case .success(let response):
          var textResponse: String = ""
          var audioResponse: String = ""
          
          // harvest the text from message.audio.transcript or message.content
          if let sentence = response.choices?.first?.message.content {
            textResponse = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if self.generalSettings.useCache {
              var cacheEntry = CacheEntry(tiles: self.selectedTiles, text: textResponse, audio: "")
              self.cache.add(cacheEntry: cacheEntry)
              
              if tiles.allSatisfy(self.selectedTiles.contains) {
                self.generatedText = textResponse
                self.generatedAudio = ""
                return
              } else {
                print("cache entry is stale, does not match the UI: \(cacheEntry.key)")
                return
              }
            }
            
          } else {
            if case let .string(transcript) = response.choices?.first?.message.audio?["transcript"] {
              textResponse = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
              
              if case let .string(data) = response.choices?.first?.message.audio?["data"] {
                audioResponse = data
                
                if self.generalSettings.useCache {
                  // create a cache node and ad/update the cache
                  var cacheEntry = CacheEntry(tiles: self.selectedTiles, text: textResponse, audio: data)
                  self.cache.add(cacheEntry: cacheEntry)
                  print("to cache: \(cacheEntry.key)")
                  
                  // now, lets see if what we just completed matches the current selection and if so, commit our changes
                  if tiles.allSatisfy(self.selectedTiles.contains) {
                    self.generatedText = textResponse
                    self.generatedAudio = audioResponse
                    self.playAudio(fromBase64: data)
                    return
                  } else {
                    print("cache entry is stale, does not match the UI: \(cacheEntry.key)")
                    return
                  }
                }
                self.playAudio(fromBase64: data)
              }
            }
          }
          self.generatedText = textResponse
          self.generatedAudio = audioResponse
          
        case .failure(let error):
          self.generatedText = "Error generating sentence: \(error.localizedDescription)"
            //
        }
      }
    }
  }
  
  func playAudio(fromBase64 base64String: String) {
    DispatchQueue.main.async {
      guard let audioData = Data(base64Encoded: base64String) else {
        print("Failed to decode Base64 string")
        return
      }
      
      do {
        print("b64: \(base64String.count), decoded: \(audioData.count)")
        self.audioPlayer = try AVAudioPlayer(data: audioData)
        self.audioPlayer?.delegate = self
        self.audioPlayer?.play()
      } catch {
        print("Failed to play audio: \(error)")
      }
    }
  }
  
  // MARK: - AVAudioPlayerDelegate
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if flag {
      print("Audio finished playing successfully.")
    } else {
      print("Audio playback finished with an error.")
    }
    
    // Clean up after playback is complete
    /*DispatchQueue.main.asyncAfter(deadline: .now() + 3.0){
      self.audioPlayer = nil
      print("3 seconds later, kill the player")
    }*/
  }
  
  // bootstrap from mock data
  override init() {
    super.init()
    let config = OpenAISwift.Config.makeDefaultOpenAI(apiKey: Config.openAIAPIKey)
    openAIClient = OpenAISwift(config: config)
    
  }

  
  final class ApiTimer: ObservableObject, Identifiable {
    enum TimerState {
      case active
      case paused
      case resumed
      case not_started
      case overtime
      case stopped
    }
    
    let id = UUID()
    
    @Published var durationString: String = ""
    @Published var secondsToCompletion: TimeInterval = 0
    @Published var overtime = false
    @Published var overtimeSeconds: TimeInterval = 0
    @Published var progress: Float = 0.0
    @Published var lastObservedDate = Date()
    
    private var alarmClosure: (() -> Void)? = nil
    private var alarmFired = false
    private var alarmSeconds: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var state: TimerState = .not_started
    
    private var timer = Timer()
    
    init() {
      duration = 0
      secondsToCompletion = 0
    }
    
    public func getElapsedTime() -> TimeInterval {
      if (!overtime) {
        return duration - secondsToCompletion
      } else {
        return duration + overtimeSeconds
      }
    }
    
    func setAlarm(after: TimeInterval, closure: @escaping () -> Void) {
      startTimer()
      alarmClosure = closure
      alarmSeconds = after
    }
    
    
    func startTimer() {
      alarmClosure = nil
      alarmFired = false
      
      timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
        guard let self else { return }
        
        let currentDate = Date()
        let currentAccumulation = currentDate.timeIntervalSince(lastObservedDate)
        lastObservedDate = Date()
        
        if (self.state == .overtime) {
          
          // in overtime mode, this counter accumlates the amount of time that has passed since duration target  was hit
          // progress is pegged at 100%
          self.secondsToCompletion += currentAccumulation
          self.overtimeSeconds += currentAccumulation
          
          if (self.overtimeSeconds < 10 && self.duration != 0) {
            //  playAlert()
          }
          
        } else {
          self.secondsToCompletion -= currentAccumulation
          self.progress = Float(self.secondsToCompletion) / Float(self.duration)
          
          // We can't do <= here because we need the time from T-1 seconds to
          // T-0 seconds to animate through first
          if self.secondsToCompletion < 0 {
            self.setState(state: .overtime)
            self.secondsToCompletion = 0
            self.overtime = true
            if (self.duration > 0) {
              //playAlert()
            }
          }
        }
        
        if (self.alarmClosure != nil && self.alarmFired == false) {
          if (getElapsedTime() > self.alarmSeconds) {
            let closure = self.alarmClosure
            self.alarmClosure = nil
            self.alarmFired = true
            closure?()
          }
        }
      })
    }
    
    public func setState(state: TimerState) -> Void {
      switch state {
      case .not_started:
        timer.invalidate()
        secondsToCompletion = duration
        progress = 0
        overtime = false
        overtimeSeconds = 0
        self.state = state
        
      case .active:
        // todo(markl) guard against already being in the active state
        self.state = state
        self.lastObservedDate = Date()
        secondsToCompletion = duration
        progress = 1.0
        startTimer()
        
      case .paused, .stopped:
        timer.invalidate()
        self.lastObservedDate = Date()
        self.state = state
        
      case .resumed:
        self.lastObservedDate = Date()
        if (overtime) {
          self.state = .overtime
          startTimer()
        } else {
          self.state = state
          startTimer()
        }
        
      case .overtime:
        self.state = state
        progress = 1.0
      }
    }
  }
}

