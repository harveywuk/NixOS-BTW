{ den, ... }:
{
  den.aspects.vesktop.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      programs.vesktop = {
        enable = true;
        settings = {
          minimizeToTray = false;
          tray = true;
        };
        vencord = {
          extraQuickCss = /* css */ ''
            /*Highlight text select color */
            [role="textbox"] *::selection {
              background: #7081d0 !important;
            }
          '';
          themes.dracula = /* css */ ''
            /**
             * @name Dracula Vesktop Theme Enhanced
             * @author CtorW
             * @version 2.0.0
             * @description A highly customizable Dracula theme for Vesktop, built on a custom, stable base.
             * @website https://github.com/CtorW
             * @source https://github.com/CtorW/DiscordDracula
            */

            /* --- CORE --- */
            @import url('https://raw.githubusercontent.com/CtorW/Vesktop-Discord/refs/heads/main/DraC/DraculaDscrd.css');

            /* --- FONT  --- */
            @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;500;600&display=swap');

            /* --- Dracula palette definition --- */
            :root {
              --dracula-background: #282a36;
              --dracula-background-alt: #343746;
              --dracula-current-line: #44475a;
              --dracula-selection: #44475a;
              --dracula-foreground: #f8f8f2;
              --dracula-comment: #6272a4;
              --dracula-cyan: #8be9fd;
              --dracula-green: #50fa7b;
              --dracula-orange: #ffb86c;
              --dracula-pink: #ff79c6;
              --dracula-purple: #bd93f9;
              --dracula-red: #ff5555;
              --dracula-yellow: #f1fa8c;
            }

            /* --- Feature & layout variables --- */
            body {
                --font: 'Inter';
                --code-font: 'Fira Code';

                --custom-dms-icon: custom;
                --dms-icon-svg-url: url('https://raw.githubusercontent.com/CtorW/Vesktop-Discord/refs/heads/main/data/DracIcon.svg');
                --dms-icon-svg-size: 90%;
                --dms-icon-color-before: var(--icon-secondary);
                --dms-icon-color-after: var(--white);
            }

            /* --- Dracula color mapping --- */
            :root {
                --colors: on;

                /* text */
                --text-0: var(--dracula-background);
                --text-1: var(--dracula-foreground);
                --text-2: var(--dracula-foreground);
                --text-3: var(--dracula-foreground);
                --text-4: var(--dracula-comment);
                --text-5: var(--dracula-comment);

                /* backgrounds */
                --bg-1: var(--dracula-current-line);
                --bg-2: var(--dracula-selection);
                --bg-3: var(--dracula-background-alt);
                --bg-4: var(--dracula-background);
                --hover: rgba(68, 71, 90, 0.5);
                --active: var(--dracula-current-line);
                --active-2: rgba(68, 71, 90, 0.7);
                --message-hover: rgba(0, 0, 0, 0.1);

                /* accents */
                --accent-1: var(--dracula-cyan);
                --accent-2: var(--dracula-purple);
                --accent-3: var(--dracula-purple);
                --accent-4: var(--dracula-pink);
                --accent-5: var(--dracula-current-line);
                --accent-new: var(--dracula-red);
                --mention: linear-gradient(to right, color-mix(in srgb, var(--dracula-purple), transparent 85%) 40%, transparent);
                --mention-hover: linear-gradient(to right, color-mix(in srgb, var(--dracula-purple), transparent 90%) 40%, transparent);
                --reply: linear-gradient(to right, color-mix(in srgb, var(--dracula-comment), transparent 90%) 40%, transparent);
                --reply-hover: linear-gradient(to right, color-mix(in srgb, var(--dracula-comment), transparent 95%) 40%, transparent);

                /* statuses */
                --online: var(--dracula-green);
                --dnd: var(--dracula-red);
                --idle: var(--dracula-orange);
                --streaming: var(--dracula-purple);
                --offline: var(--dracula-comment);

                /* borders */
                --border-light: rgba(0, 0, 0, 0.2);
                --border: var(--dracula-current-line);
                --button-border: transparent;
                --border-hover: var(--dracula-purple);

                /* base color palette */
                --red-1: var(--dracula-red); --red-2: var(--dracula-red); --red-3: var(--dracula-red); --red-4: var(--dracula-red); --red-5: var(--dracula-red);
                --green-1: var(--dracula-green); --green-2: var(--dracula-green); --green-3: var(--dracula-green); --green-4: var(--dracula-green); --green-5: var(--dracula-green);
                --blue-1: var(--dracula-cyan); --blue-2: var(--dracula-cyan); --blue-3: var(--dracula-cyan); --blue-4: var(--dracula-cyan); --blue-5: var(--dracula-cyan);
                --yellow-1: var(--dracula-yellow); --yellow-2: var(--dracula-yellow); --yellow-3: var(--dracula-yellow); --yellow-4: var(--dracula-yellow); --yellow-5: var(--dracula-yellow);
                --purple-1: var(--dracula-purple); --purple-2: var(--dracula-purple); --purple-3: var(--dracula-purple); --purple-4: var(--dracula-purple); --purple-5: var(--dracula-purple);
            }
          '';
          settings = {
            enabledThemes = [ "dracula.css" ];
            autoUpdate = true;
            autoUpdateNotification = true;
            useQuickCss = true;
            themeLinks = [ ];
            eagerPatches = false;
            enableReactDevtools = false;
            frameless = false;
            transparent = false;
            winCtrlQ = false;
            disableMinSize = false;
            winNativeTitleBar = false;

            plugins = {
              ChatInputButtonAPI.enabled = true;
              CommandsAPI.enabled = true;
              DynamicImageModalAPI.enabled = false;
              MemberListDecoratorsAPI.enabled = false;
              MessageAccessoriesAPI.enabled = true;
              MessageDecorationsAPI.enabled = false;
              MessageEventsAPI.enabled = true;
              MessagePopoverAPI.enabled = false;
              MessageUpdaterAPI.enabled = true;
              ServerListAPI.enabled = false;
              UserSettingsAPI.enabled = true;
              AccountPanelServerProfile.enabled = false;
              AlwaysAnimate.enabled = false;
              AlwaysExpandRoles.enabled = true;
              AlwaysTrust = {
                enabled = true;
                domain = true;
                file = true;
              };
              AnonymiseFileNames = {
                enabled = true;
                anonymiseByDefault = true;
                method = 2;
                randomisedLength = 7;
                consistent = "image";
              };
              AppleMusicRichPresence.enabled = false;
              "WebRichPresence (arRPC)".enabled = false;
              BetterFolders.enabled = false;
              BetterGifAltText.enabled = false;
              BetterGifPicker.enabled = false;
              BetterNotesBox.enabled = false;
              BetterRoleContext.enabled = false;
              BetterRoleDot = {
                enabled = true;
                bothStyles = false;
                copyRoleColorInProfilePopout = false;
              };
              BetterSessions.enabled = false;
              BetterSettings.enabled = false;
              BetterUploadButton.enabled = false;
              BiggerStreamPreview.enabled = false;
              BlurNSFW.enabled = false;
              CallTimer.enabled = false;
              ClearURLs.enabled = true;
              ClientTheme.enabled = false;
              ColorSighted.enabled = false;
              ConsoleJanitor.enabled = false;
              ConsoleShortcuts.enabled = false;
              CopyEmojiMarkdown.enabled = false;
              CopyFileContents.enabled = false;
              CopyStickerLinks.enabled = false;
              CopyUserURLs.enabled = true;
              CrashHandler.enabled = true;
              CtrlEnterSend.enabled = false;
              CustomIdle.enabled = false;
              CustomRPC.enabled = false;
              Dearrow.enabled = false;
              Decor.enabled = false;
              DisableCallIdle.enabled = false;
              DontRoundMyTimestamps.enabled = false;
              Experiments.enabled = false;
              ExpressionCloner.enabled = true;
              F8Break.enabled = false;
              FakeNitro.enabled = false;
              FakeProfileThemes.enabled = false;
              FavoriteEmojiFirst.enabled = true;
              FavoriteGifSearch.enabled = false;
              FixCodeblockGap.enabled = true;
              FixImagesQuality.enabled = false;
              FixSpotifyEmbeds.enabled = false;
              FixYoutubeEmbeds.enabled = true;
              ForceOwnerCrown.enabled = false;
              FriendInvites.enabled = false;
              FriendsSince.enabled = false;
              FullSearchContext.enabled = true;
              FullUserInChatbox.enabled = false;
              GameActivityToggle = {
                enabled = true;
                location = "PANEL";
                oldIcon = false;
              };
              GifPaste.enabled = false;
              GreetStickerPicker.enabled = false;
              HideMedia.enabled = false;
              iLoveSpam.enabled = false;
              IgnoreActivities.enabled = false;
              ImageFilename.enabled = false;
              ImageLink.enabled = true;
              ImageZoom.enabled = false;
              ImplicitRelationships.enabled = false;
              IrcColors.enabled = false;
              KeepCurrentChannel.enabled = true;
              LastFMRichPresence.enabled = false;
              LoadingQuotes.enabled = false;
              MemberCount.enabled = false;
              MentionAvatars.enabled = false;
              MessageClickActions.enabled = false;
              MessageLatency.enabled = false;
              MessageLinkEmbeds.enabled = false;
              MessageLogger = {
                enabled = true;
                collapseDeleted = true;
                deleteStyle = "text";
                ignoreBots = false;
                ignoreSelf = false;
                ignoreUsers = "";
                ignoreChannels = "";
                ignoreGuilds = "";
                logEdits = true;
                logDeletes = true;
                inlineEdits = false;
              };
              MessageTags.enabled = false;
              MoreQuickReactions.enabled = false;
              MutualGroupDMs.enabled = false;
              NewGuildSettings.enabled = false;
              NoBlockedMessages.enabled = false;
              NoDevtoolsWarning.enabled = false;
              NoF1.enabled = false;
              NoMaskedUrlPaste.enabled = false;
              NoMosaic.enabled = false;
              NoOnboardingDelay.enabled = true;
              NoPendingCount.enabled = false;
              NoProfileThemes.enabled = false;
              NoReplyMention.enabled = false;
              NoServerEmojis.enabled = false;
              NoTypingAnimation.enabled = false;
              NoUnblockToJump.enabled = false;
              NormalizeMessageLinks.enabled = false;
              NotificationVolume.enabled = false;
              OnePingPerDM = {
                enabled = false;
                channelToAffect = "both_dms";
                allowMentions = false;
                allowEveryone = false;
              };
              oneko.enabled = false;
              OpenInApp = {
                enabled = true;
                spotify = true;
                steam = true;
                epic = true;
                tidal = true;
                itunes = true;
              };
              OverrideForumDefaults.enabled = false;
              PauseInvitesForever.enabled = false;
              PermissionFreeWill.enabled = false;
              PermissionsViewer.enabled = false;
              petpet.enabled = false;
              PictureInPicture.enabled = false;
              PinDMs.enabled = false;
              PlainFolderIcon.enabled = false;
              PlatformIndicators.enabled = false;
              PreviewMessage.enabled = false;
              QuickMention.enabled = false;
              QuickReply.enabled = false;
              ReactErrorDecoder.enabled = false;
              ReadAllNotificationsButton.enabled = true;
              RelationshipNotifier.enabled = false;
              ReplaceGoogleSearch.enabled = false;
              ReplyTimestamp.enabled = false;
              RevealAllSpoilers.enabled = false;
              ReverseImageSearch.enabled = false;
              ReviewDB.enabled = false;
              RoleColorEverywhere.enabled = false;
              SecretRingToneEnabler.enabled = false;
              Summaries.enabled = false;
              SendTimestamps.enabled = false;
              ServerInfo.enabled = false;
              ServerListIndicators.enabled = false;
              ShikiCodeblocks.enabled = false;
              ShowAllMessageButtons.enabled = false;
              ShowConnections.enabled = false;
              ShowHiddenChannels.enabled = false;
              ShowHiddenThings.enabled = false;
              ShowMeYourName.enabled = false;
              ShowTimeoutDuration.enabled = false;
              SilentMessageToggle.enabled = false;
              SilentTyping = {
                enabled = true;
                isEnabled = true;
                showIcon = false;
                contextMenu = true;
              };
              SortFriendRequests.enabled = false;
              SpotifyControls.enabled = false;
              SpotifyCrack.enabled = false;
              SpotifyShareCommands.enabled = true;
              StartupTimings.enabled = false;
              StickerPaste.enabled = false;
              StreamerModeOnStream.enabled = false;
              SuperReactionTweaks.enabled = false;
              TextReplace.enabled = false;
              ThemeAttributes.enabled = false;
              Translate.enabled = false;
              TypingIndicator = {
                enabled = true;
                includeMutedChannels = false;
                includeCurrentChannel = true;
                includeBlockedUsers = false;
                indicatorMode = 3;
              };
              TypingTweaks.enabled = false;
              Unindent.enabled = false;
              UnlockedAvatarZoom.enabled = false;
              UnsuppressEmbeds.enabled = false;
              UserMessagesPronouns.enabled = false;
              UserVoiceShow.enabled = false;
              USRBG.enabled = false;
              ValidReply.enabled = false;
              ValidUser.enabled = false;
              VoiceChatDoubleClick.enabled = false;
              VcNarrator.enabled = false;
              VencordToolbox.enabled = false;
              ViewIcons.enabled = false;
              ViewRaw.enabled = false;
              VoiceDownload.enabled = false;
              VoiceMessages.enabled = false;
              VolumeBooster.enabled = false;
              WebKeybinds.enabled = true;
              WebScreenShareFixes.enabled = true;
              WhoReacted.enabled = true;
              XSOverlay.enabled = false;
              YoutubeAdblock.enabled = false;
              BadgeAPI.enabled = true;
              NoTrack = {
                enabled = true;
                disableAnalytics = true;
              };
              Settings = {
                enabled = true;
                settingsLocation = "aboveNitro";
              };
              DisableDeepLinks.enabled = true;
              SupportHelper.enabled = true;
              WebContextMenus.enabled = true;
            };

            uiElements = {
              chatBarButtons = { };
              messagePopoverButtons = { };
            };

            notifications = {
              timeout = 5000;
              position = "bottom-right";
              useNative = "not-focused";
              logLimit = 50;
            };
          };
        };
      };

      # Replace HM-managed read-only symlinks with writable copies so vesktop can write settings at runtime
      home.activation.vesktopSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        for f in \
          "$HOME/.config/vesktop/settings.json" \
          "$HOME/.config/vesktop/settings/settings.json"; do
          if [ -L "$f" ]; then
            target=$(readlink "$f")
            rm "$f"
            cp "$target" "$f"
            chmod 644 "$f"
          fi
        done
      '';

      # Create systemd service for vesktop with proper ordering
      systemd.user.services.vesktop = {
        Unit = {
          Description = "Vesktop Discord Client";
          After = lib.mkIf config.programs.noctalia.enable [
            "graphical-session.target"
            "noctalia.service"
          ];
          Wants = lib.mkIf config.programs.noctalia.enable [ "noctalia.service" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${config.programs.vesktop.package}/bin/vesktop";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
