import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import DButton from "discourse/components/d-button";
import PickFilesButton from "discourse/components/pick-files-button";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { getURLWithCDN } from "discourse/lib/get-url";
import lightbox from "discourse/lib/lightbox";
import { authorizesOneOrMoreExtensions, isImage } from "discourse/lib/uploads";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import { i18n } from "discourse-i18n";

export default class SiteSettingUpload extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked uploadedFile = null;

  uppyUpload = new UppyUpload(getOwner(this), {
    id: this.settingId,
    type: "site_setting",
    additionalParams: () => ({
      for_site_setting: true,
      site_setting_name: this.args.setting.setting,
    }),
    validateUploadedFilesOptions: this.validationOptions,
    uploadDropTargetOptions: () => ({
      target: document.querySelector(
        `#${this.settingId} .uploaded-file-preview`
      ),
    }),
    uploadDone: (upload) => {
      this.uploadedFile = upload;
      this.args.changeValueCallback(upload.url);
    },
  });

  applyLightbox = modifier(() =>
    lightbox(
      document.querySelector(`#${this.settingId}.file-uploader`),
      this.siteSettings
    )
  );

  willDestroy() {
    super.willDestroy(...arguments);
    window.pswp?.close();
  }

  get settingId() {
    return `site-setting-file-uploader-${this.args.setting.setting}`;
  }

  get inputId() {
    return `${this.settingId}__input`;
  }

  get validationOptions() {
    return this.args.setting.accepted_extensions
      ? { skipValidation: true }
      : { imagesOnly: true };
  }

  get acceptedFormats() {
    return this.args.setting.accepted_extensions || "image/*";
  }

  get isImageFile() {
    return this.args.value && isImage(this.args.value);
  }

  get disabled() {
    return (
      this.args.disabled ||
      this.notAllowed ||
      this.uppyUpload?.uploading ||
      this.uppyUpload?.processing
    );
  }

  get disabledReason() {
    if (this.disabled && this.notAllowed) {
      return i18n("post.errors.no_uploads_authorized");
    }
  }

  get notAllowed() {
    if (this.args.setting.accepted_extensions) {
      return false;
    }
    return !authorizesOneOrMoreExtensions(
      this.currentUser?.staff,
      this.siteSettings
    );
  }

  get fileCdnUrl() {
    return this.args.value ? getURLWithCDN(this.args.value) : "";
  }

  get backgroundStyle() {
    return this.isImageFile
      ? htmlSafe(`background-image: url(${this.fileCdnUrl})`)
      : htmlSafe("");
  }

  get fileName() {
    const filename =
      this.uploadedFile?.original_filename ??
      this.args.setting.upload?.original_filename;
    return filename || this.args.value?.split("/").pop();
  }

  get filesize() {
    return (
      this.uploadedFile?.human_filesize ??
      this.args.setting.upload?.human_filesize
    );
  }

  get imageWidth() {
    return this.uploadedFile?.width ?? this.args.setting.upload?.width;
  }

  get imageHeight() {
    return this.uploadedFile?.height ?? this.args.setting.upload?.height;
  }

  get progressBarStyle() {
    return htmlSafe(`width: ${this.uppyUpload.uploadProgress || 0}%`);
  }

  get showPlaceholder() {
    return !this.args.value && this.args.setting.placeholder;
  }

  get placeholderStyle() {
    return this.args.setting.placeholder
      ? htmlSafe(`background-image: url(${this.args.setting.placeholder})`)
      : htmlSafe("");
  }

  @action
  toggleLightbox() {
    const link = document.querySelector(`#${this.settingId} a.lightbox`);
    if (link) {
      lightbox(link);
      link.click();
    }
  }

  @action
  onKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      document.getElementById(this.inputId)?.click();
    }
  }

  @action
  deleteUpload() {
    this.uploadedFile = null;
    this.args.changeValueCallback(null);
  }

  <template>
    <div
      id={{this.settingId}}
      class={{concatClass
        "file-uploader"
        (if @value "has-file" "no-file")
        (if this.isImageFile "has-image")
      }}
    >
      <div
        class="uploaded-file-preview input-xxlarge"
        style={{this.backgroundStyle}}
      >
        {{#if this.showPlaceholder}}
          <div
            class="placeholder-overlay"
            style={{this.placeholderStyle}}
          ></div>
        {{/if}}

        {{#if @value}}
          {{#if this.isImageFile}}
            <a
              {{this.applyLightbox}}
              href={{this.fileCdnUrl}}
              title={{this.fileName}}
              rel="nofollow ugc noopener"
              class="lightbox"
            >
              <div class="meta">
                <span class="informations">
                  {{#if this.imageWidth}}
                    {{this.imageWidth}}x{{this.imageHeight}}
                  {{/if}}
                  {{this.filesize}}
                </span>
              </div>
            </a>

            <div class="expand-overlay">
              <DButton
                @action={{this.toggleLightbox}}
                @icon="discourse-expand"
                @title="expand"
                class="btn-default btn-small file-uploader-lightbox-btn"
              />
            </div>
          {{else}}
            <div class="file-info">
              <div class="file-icon">
                {{icon "file"}}
              </div>
              <div class="file-details">
                <span class="file-name">{{this.fileName}}</span>
                {{#if this.filesize}}
                  <span class="file-size">{{this.filesize}}</span>
                {{/if}}
              </div>
              <a
                href={{this.fileCdnUrl}}
                download={{this.fileName}}
                class="btn btn-default btn-small download-btn"
                title={{i18n "admin.site_settings.download_file"}}
              >
                {{icon "download"}}
              </a>
            </div>
          {{/if}}
        {{else}}
          <div class="file-upload-controls">
            <label
              class="btn btn-transparent
                {{if this.disabled 'disabled'}}
                {{if this.uppyUpload.uploading 'hidden'}}"
              title={{this.disabledReason}}
              for={{this.inputId}}
              tabindex="0"
              {{on "keydown" this.onKeydown}}
            >
              {{icon "upload"}}
              <PickFilesButton
                @registerFileInput={{this.uppyUpload.setup}}
                @fileInputDisabled={{this.disabled}}
                @acceptedFormatsOverride={{this.acceptedFormats}}
                @fileInputId={{this.inputId}}
              />
              {{i18n "upload_selector.select_file"}}
            </label>

            <div
              class="progress-status
                {{unless this.uppyUpload.uploading 'hidden'}}"
            >
              <div
                aria-label="{{i18n 'upload_selector.uploading'}}
              {{this.uppyUpload.uploadProgress}}%"
                role="progressbar"
                class="progress-bar-container"
              >
                <div class="progress-bar" style={{this.progressBarStyle}}></div>
              </div>

              <span>
                {{i18n "upload_selector.uploading"}}
                {{this.uppyUpload.uploadProgress}}%
              </span>
            </div>
          </div>
        {{/if}}
      </div>

      {{#if @value}}
        <div class="file-upload-controls">
          <label
            class="btn btn-default btn-small {{if this.disabled 'disabled'}}"
            title={{this.disabledReason}}
            for={{this.inputId}}
            tabindex="0"
            {{on "keydown" this.onKeydown}}
          >
            {{icon "upload"}}
            <PickFilesButton
              @registerFileInput={{this.uppyUpload.setup}}
              @fileInputDisabled={{this.disabled}}
              @acceptedFormatsOverride={{this.acceptedFormats}}
              @fileInputId={{this.inputId}}
            />
            {{i18n "upload_selector.change"}}
          </label>
          <DButton
            @action={{this.deleteUpload}}
            @icon="trash-can"
            @disabled={{this.disabled}}
            @label="upload_selector.delete"
            class="btn-danger btn-small"
          />
        </div>
      {{/if}}
    </div>
  </template>
}
