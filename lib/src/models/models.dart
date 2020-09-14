// Copyright 2020 Joan Pablo Jiménez Milian. All rights reserved.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// This is the base class for [FormGroup], [FormArray] and [FormControl].
///
/// It provides some of the shared behavior that all controls and groups have,
/// like running validators, calculating status, and resetting state.
///
/// It also defines the properties that are shared between all sub-classes,
/// like value and valid.
///
/// It shouldn't be instantiated directly.
abstract class AbstractControl<T> {
  final _statusChanges = StreamController<ControlStatus>.broadcast();
  final _valueChanges = StreamController<T>.broadcast();
  final _touchChanges = StreamController<bool>.broadcast();
  final List<ValidatorFunction> _validators;
  final List<AsyncValidatorFunction> _asyncValidators;

  StreamSubscription _asyncValidationSubscription;
  Map<String, dynamic> _errors = {};
  bool _pristine = true;

  T _value;

  ControlStatus _status;

  /// The parent control.
  AbstractControl _parent;

  /// Async validators debounce timer.
  Timer _debounceTimer;

  /// Async validators debounce time in milliseconds.
  final int _asyncValidatorsDebounceTime;

  bool _touched = false;

  /// Constructor of the [AbstractControl].
  AbstractControl({
    List<ValidatorFunction> validators,
    List<AsyncValidatorFunction> asyncValidators,
    int asyncValidatorsDebounceTime = 250,
    bool disabled = false,
    bool touched = false,
  })  : assert(asyncValidatorsDebounceTime >= 0),
        _validators = validators ?? const [],
        _asyncValidators = asyncValidators ?? const [],
        _asyncValidatorsDebounceTime = asyncValidatorsDebounceTime {
    _status = disabled ? ControlStatus.disabled : ControlStatus.valid;
    _touched = touched ?? false;
  }

  /// A control is `dirty` if the user has changed the value in the UI.
  ///
  /// Gets true if the user has changed the value of this control in the UI.
  ///
  /// Programmatic changes to a control's value do not mark it dirty.
  ///
  /// See also [pristine].
  bool get dirty => !this.pristine;

  /// A control is `pristine` if the user has not yet changed the value
  /// in the UI.
  ///
  /// Gets true if the user has not yet changed the value in the UI.
  /// Programmatic changes to a control's value do not mark it dirty.
  ///
  /// See also [dirty].
  bool get pristine => this._pristine;

  /// Gets if the control is touched or not.
  ///
  /// A control is touched when the user taps on the ReactiveFormField widget
  /// and then remove focus or completes the text edition. Validation messages
  /// will begin to show up when the FormControl is touched.
  bool get touched => _touched;

  /// The list of functions that determines the validity of this control.
  ///
  /// In [FormGroup] these come in handy when you want to perform validation
  /// that considers the value of more than one child control.
  List<ValidatorFunction> get validators => List.unmodifiable(_validators);

  /// The list of async functions that determines the validity of this control.
  ///
  /// In [FormGroup] these come in handy when you want to perform validation
  /// that considers the value of more than one child control.
  List<AsyncValidatorFunction> get asyncValidators =>
      List.unmodifiable(_asyncValidators);

  /// The current value of the control.
  T get value => _value;

  /// Sets the value to the control
  set value(T value) {
    this.updateValue(value);
  }

  /// Gets the parent control.
  AbstractControl get parent => this._parent;

  /// Sets the parent of the control.
  set parent(AbstractControl parent) {
    this._parent = parent;
  }

  /// An object containing any errors generated by failing validation,
  /// or empty [Map] if there are no errors.
  Map<String, dynamic> get errors => Map.unmodifiable(_errors);

  /// A [Stream] that emits the status every time it changes.
  Stream<ControlStatus> get statusChanged => _statusChanges.stream;

  /// A [Stream] that emits the value of the control every time it changes.
  Stream<T> get valueChanges => _valueChanges.stream;

  /// A [Stream] that emits an event every time the control
  /// is touched or untouched.
  Stream<bool> get touchChanges => _touchChanges.stream;

  /// A control is valid when its [status] is ControlStatus.valid.
  bool get valid => this.status == ControlStatus.valid;

  /// A control is invalid when its [status] is ControlStatus.invalid.
  bool get invalid => this.status == ControlStatus.invalid;

  /// A control is pending when its [status] is ControlStatus.pending.
  bool get pending => this.status == ControlStatus.pending;

  /// A control is disabled when its [status] is ControlStatus.disabled.
  bool get disabled => this.status == ControlStatus.disabled;

  /// A control is enabled as long as its [status] is
  /// not ControlStatus.disabled.
  bool get enabled => !this.disabled;

  /// True whether the control has validation errors.
  bool get hasErrors => this.errors.isNotEmpty;

  /// The validation status of the control.
  ///
  /// There are four possible validation status values:
  /// * VALID: This control has passed all validation checks.
  /// * INVALID: This control has failed at least one validation check.
  /// * PENDING: This control is in the midst of conducting a validation check.
  ///
  /// These status values are mutually exclusive, so a control cannot be both
  /// valid AND invalid or invalid AND pending.
  ControlStatus get status => _status;

  /// Marks the control as `dirty`.
  ///
  /// A control becomes dirty when the control's value is changed through
  /// the UI.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  ///
  /// When [emitEvent] is true or not supplied (the default), the
  /// *statusChanges* emit event with the latest status when the control is
  /// mark dirty. When false, no events are emitted.
  void markAsDirty({bool updateParent, bool emitEvent}) {
    updateParent ??= true;
    emitEvent ??= true;

    _pristine = false;

    if (emitEvent) {
      _statusChanges.add(_status);
    }

    if (_parent != null && updateParent) {
      _parent.markAsDirty(updateParent: updateParent, emitEvent: emitEvent);
    }
  }

  /// Marks the control as `pristine`.
  ///
  /// If the control has any children, marks all children as `pristine`, and
  /// recalculates the `pristine` status of all parent controls.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  void markAsPristine({bool updateParent}) {
    updateParent ??= true;

    _pristine = true;

    _forEachChild((control) => control.markAsPristine(updateParent: false));

    if (_parent != null && updateParent) {
      _parent._updatePristine(updateParent: updateParent);
    }
  }

  /// Marks the control as touched.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  ///
  /// When [emitEvent] is true or not supplied (the default), an
  /// event is emitted.
  void markAsTouched({bool updateParent, bool emitEvent}) {
    updateParent ??= true;
    emitEvent ??= true;

    if (!_touched) {
      _touched = true;

      if (emitEvent) {
        _touchChanges.add(_touched);
      }

      if (_parent != null && updateParent) {
        _parent.markAsTouched(updateParent: updateParent, emitEvent: false);
      }
    }
  }

  /// Marks the control and all its descendant controls as touched.
  ///
  /// When [updateParent] is false, mark only this control and descendants.
  /// When true or not supplied, marks also all direct ancestors.
  /// Default is true.
  ///
  /// When [emitEvent] is true or not supplied (the default), a notification
  /// event is emitted.
  void markAllAsTouched({bool updateParent, bool emitEvent}) {
    this.markAsTouched(updateParent: updateParent);
    _forEachChild((control) => control.markAllAsTouched(updateParent: false));
  }

  /// Marks the control as untouched.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  ///
  /// When [emitEvent] is true or not supplied (the default), a notification
  /// event is emitted.
  void markAsUntouched({bool updateParent, bool emitEvent}) {
    updateParent ??= true;
    emitEvent ??= true;

    if (_touched) {
      _touched = false;
      _forEachChild((control) => control.markAsUntouched(updateParent: false));

      if (emitEvent) {
        _touchChanges.add(_touched);
      }

      if (_parent != null && updateParent) {
        _parent._updateTouched(updateParent: updateParent);
      }
    }
  }

  /// Enables the control. This means the control is included in validation
  /// checks and the aggregate value of its parent. Its status recalculates
  /// based on its value and its validators.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  ///
  /// When [emitEvent] is true or not supplied (the default), a notification
  /// event is emitted.
  void markAsEnabled({bool updateParent, bool emitEvent}) {
    emitEvent ??= true;
    updateParent ??= true;

    if (this.enabled) {
      return;
    }
    _status = ControlStatus.valid;
    this.updateValueAndValidity(updateParent: true, emitEvent: emitEvent);
    _updateAncestors(updateParent);
  }

  /// Disables the control.
  ///
  /// This means the control is exempt from validation checks and excluded
  /// from the aggregate value of any parent. Its status is `DISABLED`.
  ///
  /// If the control has children, all children are also disabled.
  ///
  /// When [updateParent] is false, mark only this control. When true or not
  /// supplied, marks all direct ancestors. Default is true.
  void markAsDisabled({bool updateParent, bool emitEvent}) {
    updateParent ??= true;
    emitEvent ??= true;

    _errors.clear();
    _status = ControlStatus.disabled;
    if (emitEvent) {
      _statusChanges.add(_status);
    }
    _updateAncestors(updateParent);
  }

  /// Disposes the control
  void dispose() {
    _statusChanges.close();
    _valueChanges.close();
    _asyncValidationSubscription?.cancel();
  }

  /// Sets the value of the control.
  ///
  /// When [updateParent] is true or not supplied (the default) each change
  /// affects this control and its parent, otherwise only affects to this
  /// control.
  ///
  /// When [emitEvent] is true or not supplied (the default), both the
  /// *statusChanges* and *valueChanges* emit events with the latest status
  /// and value when the control is reset. When false, no events are emitted.
  void updateValue(T value, {bool updateParent, bool emitEvent});

  /// Resets the form control, marking it as untouched,
  /// and setting the value to null.
  ///
  /// The argument [value] is optional and resets the control with an initial
  /// value.
  ///
  /// ### FormControl example
  /// ```dart
  /// final control = FormControl<String>();
  ///
  /// control.reset(value: 'John Doe');
  ///
  /// print(control.value); // output: 'John Doe'
  ///
  /// ```
  ///
  /// ### FormGroup example
  /// ```dart
  /// final form = FormGroup({
  ///   'first': FormControl(value: 'first name'),
  ///   'last': FormControl(value: 'last name'),
  /// });
  ///
  /// print(form.value);   // output: {first: 'first name', last: 'last name'}
  ///
  /// form.reset(value: { 'first': 'John', 'last': 'last name' });
  ///
  /// print(form.value); // output: {first: 'John', last: 'last name'}
  ///
  /// ```
  ///
  /// ### FormArray example
  /// ````dart
  /// final array = FormArray<String>([
  ///   FormControl<String>(),
  ///   FormControl<String>(),
  /// ]);
  ///
  /// array.reset(value: ['name', 'last name']);
  ///
  /// print(array.value); // output: ['name', 'last name']
  ///
  /// ```
  ///
  /// The argument [disabled] is optional and resets the disabled status of the
  /// control.
  ///
  /// When [updateParent] is true or not supplied (the default) each change
  /// affects this control and its parent, otherwise only affects to this
  /// control.
  ///
  /// When [emitEvent] is true or not supplied (the default), both the
  /// *statusChanges* and *valueChanges* events notify listeners with the
  /// latest status and value when the control is reset. When false, no events
  /// are emitted.
  void reset({
    T value,
    bool disabled,
    bool updateParent,
    bool emitEvent,
  }) {
    this.markAsPristine(updateParent: updateParent);
    this.markAsUntouched(updateParent: updateParent);

    this.updateValue(value, updateParent: updateParent, emitEvent: emitEvent);

    if (disabled != null) {
      disabled
          ? markAsDisabled(updateParent: true, emitEvent: false)
          : markAsEnabled(updateParent: true, emitEvent: false);
    }
  }

  /// Sets errors on a form control when running validations manually,
  /// rather than automatically.
  void setErrors(Map<String, dynamic> errors) {
    _errors.clear();
    _errors.addAll(errors);

    _updateControlsErrors();
    this.markAsDirty(emitEvent: false);
  }

  /// Returns true if all children disabled, otherwise returns false.
  bool _allControlsDisabled() {
    return this.disabled;
  }

  /// Returns true if all children has the specified [status], otherwise
  /// returns false.
  bool _anyControlsHaveStatus(ControlStatus status) {
    return false;
  }

  ControlStatus _calculateStatus() {
    if (_allControlsDisabled()) {
      return ControlStatus.disabled;
    } else if (this.hasErrors) {
      return ControlStatus.invalid;
    } else if (_anyControlsHaveStatus(ControlStatus.pending)) {
      return ControlStatus.pending;
    } else if (_anyControlsHaveStatus(ControlStatus.invalid)) {
      return ControlStatus.invalid;
    }

    return ControlStatus.valid;
  }

  _updateControlsErrors() {
    _status = _calculateStatus();
    _statusChanges.add(_status);

    if (_parent != null) {
      _parent._updateControlsErrors();
    }
  }

  Map<String, dynamic> _runValidators() {
    final errors = Map<String, dynamic>();
    this.validators.forEach((validator) {
      final error = validator(this);
      if (error != null) {
        errors.addAll(error);
      }
    });

    return errors;
  }

  void _setInitialStatus() {
    _status = this._allControlsDisabled()
        ? ControlStatus.disabled
        : ControlStatus.valid;
  }

  void _updateAncestors(bool updateParent) {
    if (_parent != null && updateParent) {
      _parent.updateValueAndValidity(updateParent: updateParent);
    }
  }

  void _updateValue() {
    _value = this._reduceValue();
  }

  void updateValueAndValidity({bool updateParent, bool emitEvent}) {
    emitEvent ??= true;
    updateParent ??= true;

    _setInitialStatus();
    _updateValue();
    if (this.enabled) {
      _cancelExistingSubscription();
      _errors = _runValidators();
      _status = _calculateStatus();
      if (_status == ControlStatus.valid || _status == ControlStatus.pending) {
        _runAsyncValidators();
      }
    }

    if (emitEvent) {
      _valueChanges.add(this.value);
      _statusChanges.add(_status);
    }

    _updateAncestors(updateParent);
  }

  Future<void> _cancelExistingSubscription() async {
    if (_asyncValidationSubscription != null) {
      await _asyncValidationSubscription.cancel();
      _asyncValidationSubscription = null;
    }
  }

  /// runs async validators to validate the value of current control
  Future<void> _runAsyncValidators() async {
    if (_asyncValidators.isEmpty) {
      return;
    }

    this._status = ControlStatus.pending;

    if (_debounceTimer != null) {
      _debounceTimer.cancel();
    }

    _debounceTimer = Timer(
      Duration(milliseconds: _asyncValidatorsDebounceTime),
      () {
        final validatorsStream = Stream.fromFutures(
            this.asyncValidators.map((validator) => validator(this)));

        final errors = Map<String, dynamic>();
        _asyncValidationSubscription = validatorsStream.listen(
          (error) {
            if (error != null) {
              errors.addAll(error);
            }
          },
          onDone: () {
            this.setErrors(errors);
          },
        );
      },
    );
  }

  void _updateTouched({bool updateParent}) {
    _touched = _anyControlsTouched();

    if (_parent != null && updateParent) {
      _parent._updateTouched(updateParent: updateParent);
    }
  }

  void _updatePristine({bool updateParent}) {
    _pristine = !_anyControlsDirty();

    if (_parent != null && updateParent) {
      _parent._updatePristine(updateParent: updateParent);
    }
  }

  bool _anyControlsTouched() => _anyControls((control) => control.touched);

  bool _anyControlsDirty() => _anyControls((control) => control.dirty);

  bool _anyControls(bool Function(AbstractControl) condition);

  T _reduceValue();

  void _forEachChild(void Function(AbstractControl) callback);
}

/// Tracks the value and validation status of an individual form control.
class FormControl<T> extends AbstractControl<T> {
  final _focusChanges = StreamController<bool>.broadcast();
  bool _focused = false;

  /// Creates a new FormControl instance.
  ///
  /// The control can optionally be initialized with a [defaultValue].
  ///
  /// The control can optionally have [validators] that validates
  /// the control each time the value changes.
  ///
  /// The control can optionally have [asyncValidators] that validates
  /// asynchronously the control each time the value changes.
  ///
  /// You can set an [asyncValidatorsDebounceTime] in millisecond to set
  /// a delay time before trigger async validators. This is useful for
  /// minimizing request to a server. The default value is 250 milliseconds.
  ///
  /// You can set [touched] as true to force the validation messages
  /// to show up at the very first time the widget that is bound to this
  /// control builds in the UI.
  ///
  /// ### Example:
  /// ```dart
  /// final priceControl = FormControl<double>(defaultValue: 0.0);
  /// ```
  ///
  FormControl({
    T value,
    List<ValidatorFunction> validators,
    List<AsyncValidatorFunction> asyncValidators,
    int asyncValidatorsDebounceTime = 250,
    bool touched = false,
    bool disabled = false,
  }) : super(
          validators: validators,
          asyncValidators: asyncValidators,
          asyncValidatorsDebounceTime: asyncValidatorsDebounceTime,
          disabled: disabled,
          touched: touched,
        ) {
    if (value != null) {
      this.value = value;
    } else {
      this.updateValueAndValidity();
    }
  }

  /// True if the control is marked as focused.
  bool get focused => _focused;

  /// Disposes the control
  @override
  void dispose() {
    _focusChanges.close();
    super.dispose();
  }

  /// A [ChangeNotifier] that emits an event every time the focus status of
  /// the control changes.
  Stream<bool> get focusChanges => _focusChanges.stream;

  /// Remove focus on a ReactiveFormField widget without the interaction
  /// of the user.
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final formControl = form.formControl('name');
  ///
  /// // UI text field lose focus
  /// formControl.unfocus();
  ///```
  ///
  void unfocus() {
    if (this.focused) {
      _updateFocused(false);
    }
  }

  /// Sets focus on a ReactiveFormField widget without the interaction
  /// of the user.
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final formControl = form.formControl('name');
  ///
  /// // UI text field get focus and the device keyboard pop up
  /// formControl.focus();
  ///```
  ///
  void focus() {
    if (!this.focused) {
      _updateFocused(true);
    }
  }

  void _updateFocused(bool value) {
    _focused = value;
    _focusChanges.add(value);
  }

  /// This method is for internal use only.
  @override
  T _reduceValue() => this.value;

  @override
  void updateValue(T value, {bool updateParent, bool emitEvent}) {
    if (_value != value) {
      _value = value;
      this.updateValueAndValidity(
        updateParent: updateParent,
        emitEvent: emitEvent,
      );
    }
  }

  @override
  void _forEachChild(void Function(AbstractControl) callback) => [];

  @override
  bool _anyControls(bool Function(AbstractControl) condition) => false;
}

/// Tracks the value and validity state of a group of FormControl instances.
///
/// A FormGroup aggregates the values of each child FormControl into one object,
/// with each control name as the key.
///
/// It calculates its status by reducing the status values of its children.
/// For example, if one of the controls in a group is invalid, the entire group
/// becomes invalid.
class FormGroup extends AbstractControl<Map<String, dynamic>>
    with FormControlCollection {
  final Map<String, AbstractControl> _controls = {};

  /// Creates a new FormGroup instance.
  ///
  /// When instantiating a [FormGroup], pass in a [Map] of child controls
  /// as the first argument.
  ///
  /// The key for each child registers the name for the control.
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final form = FromGroup({
  ///   'name': FormControl(defaultValue: 'John Doe'),
  ///   'email': FormControl(),
  /// });
  /// ```
  /// You can also set [validators] as optionally argument.
  ///
  /// See also [AbstractControl.validators]
  FormGroup(
    Map<String, AbstractControl> controls, {
    List<ValidatorFunction> validators,
  })  : assert(controls != null),
        super(validators: validators) {
    this.addAll(controls);
  }

  @override
  bool contains(String name) {
    return this._controls.containsKey(name);
  }

  /// Retrieves a child control given the control's [name] or path.
  ///
  /// The argument [name] is a dot-delimited string that define the path to the
  /// control.
  ///
  /// Throws [FormControlNotFoundException] if no control founded with
  /// the specified [name]/path.
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final form = FormGroup({
  ///   'total': FormControl<int>(value: 20),
  ///   'person': FormGroup({
  ///     'name': FormControl<String>(value: 'John'),
  ///   }),
  /// });
  /// ```
  ///
  /// Retrieves a control
  /// ```dart
  /// form.control('total');
  /// ```
  ///
  /// Retrieves a nested control
  /// ```dart
  /// form.control('person.name');
  /// ```
  @override
  AbstractControl control(String name) {
    final namePath = name.split('.');
    if (namePath.length > 1) {
      final control = this.findControl(namePath);
      if (control != null) {
        return control;
      }
    } else if (this.contains(name)) {
      return _controls[name];
    }

    throw FormControlNotFoundException(controlName: name);
  }

  /// Gets the collection of child controls.
  ///
  /// The key for each child is the name under which it is registered.
  Map<String, AbstractControl> get controls => Map.unmodifiable(this._controls);

  /// Reduce the value of the group is a key-value pair for each control
  /// in the group.
  ///
  /// ### Example:
  ///
  ///```dart
  /// final form = FormGroup({
  ///   'name': FormControl(defaultValue: 'John Doe'),
  ///   'email': FormControl(defaultValue: 'johndoe@email.com'),
  /// });
  ///
  /// print(form.value);
  ///```
  ///
  /// ```json
  /// { "name": "John Doe", "email": "johndoe@email.com" }
  ///```
  ///
  /// This method is for internal use only.
  @override
  Map<String, dynamic> _reduceValue() {
    final map = Map<String, dynamic>();
    _controls.forEach((key, control) {
      if (control.enabled || this.disabled) {
        map[key] = control.value;
      }
    });

    return map;
  }

  /// Set the complete value for the form group.
  ///
  /// ### Example
  ///
  /// ```dart
  /// final form = FormGroup({
  ///   'name': FormControl(),
  ///   'email': FormControl(),
  /// });
  ///
  /// form.value = { 'name': 'John Doe', 'email': 'johndoe@email.com' }
  ///
  /// print(form.value);
  /// ```
  /// ```json
  /// { "name": "John Doe", "email": "johndoe@email.com" }
  ///```
  @override
  set value(Map<String, dynamic> value) {
    this.updateValue(value);
  }

  /// Disables the control.
  ///
  /// This means the control is exempt from validation checks and excluded
  /// from the aggregate value of any parent. Its status is `DISABLED`.
  ///
  /// If the control has children, all children are also disabled.
  ///
  /// When [updateParent] is true, mark only this control.
  /// When false or not supplied, marks all direct ancestors.
  /// Default is false.
  @override
  void markAsDisabled({bool updateParent, bool emitEvent}) {
    _controls.forEach((_, control) {
      control.markAsDisabled(updateParent: true, emitEvent: emitEvent);
    });
    super.markAsDisabled(updateParent: updateParent, emitEvent: emitEvent);
  }

  /// Enables the control.
  ///
  /// This means the control is included in validation checks and the aggregate
  /// value of its parent. Its status recalculates based on its value and its
  /// validators.
  ///
  /// When [updateParent] is true, mark only this control.
  /// When false or not supplied, marks all direct ancestors.
  /// Default is false.
  @override
  void markAsEnabled({bool updateParent, bool emitEvent}) {
    _controls.forEach((_, control) {
      control.markAsEnabled(updateParent: true, emitEvent: emitEvent);
    });
    super.markAsEnabled(updateParent: updateParent, emitEvent: emitEvent);
  }

  /// Appends all [controls] to the group.
  void addAll(Map<String, AbstractControl> controls) {
    _controls.addAll(controls);
    controls.forEach((name, control) {
      control.parent = this;
    });
    this.updateValueAndValidity();
    _updateTouched();
  }

  /// Disposes the group.
  @override
  void dispose() {
    _forEachChild((control) {
      control.parent = null;
      control.dispose();
    });
    this.closeCollectionEvents();
    super.dispose();
  }

  /// Returns true if all children disabled, otherwise returns false.
  ///
  /// This is for internal use only.
  @override
  bool _allControlsDisabled() {
    if (_controls.isEmpty) {
      return false;
    }
    return _controls.values.every((control) => control.disabled);
  }

  /// Returns true if all children has the specified [status], otherwise
  /// returns false.
  ///
  /// This is for internal use only.
  @override
  bool _anyControlsHaveStatus(ControlStatus status) {
    return _controls.values.any((control) => control.status == status);
  }

  /// Gets all errors of the group.
  ///
  /// Contains all the errors of the group and the child errors.
  @override
  Map<String, dynamic> get errors {
    final allErrors = Map.of(super.errors);
    _controls.forEach((name, control) {
      if (control.enabled && control.hasErrors) {
        allErrors.update(
          name,
          (_) => control.errors,
          ifAbsent: () => control.errors,
        );
      }
    });

    return allErrors;
  }

  @override
  void updateValue(
    Map<String, dynamic> value, {
    bool updateParent = true,
    bool emitEvent = true,
  }) {
    value ??= {};

    _controls.keys.forEach((name) {
      _controls[name].updateValue(
        value[name],
        updateParent: false,
        emitEvent: emitEvent,
      );
    });

    this.updateValueAndValidity(
      updateParent: updateParent,
      emitEvent: emitEvent,
    );
  }

  /// Resets the `FormGroup`, marks all descendants as *untouched*, and sets
  /// the value of all descendants to null.
  ///
  /// You reset to a specific form [state] by passing in a map of states
  /// that matches the structure of your form, with control names as keys.
  /// The control state is an object with both a value and a disabled status.
  ///
  /// ### Reset the form group values and disabled status
  ///
  /// ```dart
  /// final form = FormGroup({
  ///   'first': FormControl('first name'),
  ///   'last': FormControl('last name'),
  /// });
  ///
  /// form.resetState({
  ///   'first': ControlState(value: 'name', disabled: true),
  ///   'last': ControlState(value: 'last'),
  /// });
  ///
  /// print(form.value);  // output: {first: 'name', last: 'last name'}
  /// print(form.control('first').disabled);  // output: true
  /// ```
  void resetState(Map<String, ControlState> state) {
    if (state == null || state.isEmpty) {
      this.reset();
    } else {
      _controls.forEach((name, control) {
        control.reset(
          value: state[name]?.value,
          disabled: state[name]?.disabled,
          updateParent: false,
        );
      });
      _updatePristine();
      this.updateValueAndValidity();
    }
  }

  @override
  void _forEachChild(void Function(AbstractControl) callback) {
    _controls.forEach((name, control) => callback(control));
  }

  @override
  bool _anyControls(bool Function(AbstractControl) condition) {
    return _controls.values
        .any((control) => control.enabled && condition(control));
  }
}

/// A FormArray aggregates the values of each child FormControl into an array.
///
/// It calculates its status by reducing the status values of its children.
/// For example, if one of the controls in a FormArray is invalid, the entire
/// array becomes invalid.
///
/// FormArray is one of the three fundamental building blocks used to define
/// forms in Reactive Forms, along with [FormControl] and [FormGroup].
class FormArray<T> extends AbstractControl<Iterable<T>>
    with FormControlCollection {
  final List<AbstractControl<T>> _controls = [];

  /// Creates a new [FormArray] instance.
  ///
  /// When instantiating a [FormGroup], pass in a collection of child controls
  /// as the first argument.
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final form = FromGroup({
  ///   'name': FormControl(defaultValue: 'John Doe'),
  ///   'aliases': FormArray([
  ///     FormControl(defaultValue: 'john'),
  ///     FormControl(defaultValue: 'little john'),
  ///   ]),
  /// });
  /// ```
  /// You can also set [validators] as optionally argument.
  ///
  /// See also [AbstractControl.validators]
  FormArray(
    Iterable<AbstractControl<T>> controls, {
    List<ValidatorFunction> validators,
  })  : assert(controls != null),
        super(validators: validators) {
    this.addAll(controls);
  }

  /// Gets the list of child controls.
  List<AbstractControl<T>> get controls => List.unmodifiable(_controls);

  /// Sets the value of the [FormArray].
  ///
  /// It accepts an array that matches the structure of the control.
  /// It accepts both super-sets and sub-sets of the array.
  @override
  set value(Iterable<T> value) {
    this.updateValue(value);
  }

  /// Gets the values of controls as an [Iterable].
  ///
  /// This method is for internal use only.
  @override
  List<T> _reduceValue() {
    return this
        ._controls
        .where((control) => control.enabled || this.disabled)
        .map((control) => control.value)
        .toList();
  }

  /// Disables the control.
  ///
  /// This means the control is exempt from validation checks and excluded
  /// from the aggregate value of any parent. Its status is `DISABLED`.
  ///
  /// If the control has children, all children are also disabled.
  ///
  /// When [updateParent] is true, mark only this control.
  /// When false or not supplied, marks all direct ancestors.
  /// Default is false.
  @override
  void markAsDisabled({bool updateParent = true, bool emitEvent = true}) {
    _controls.forEach((control) {
      control.markAsDisabled(updateParent: true, emitEvent: emitEvent);
    });
    super.markAsDisabled(updateParent: updateParent, emitEvent: emitEvent);
  }

  /// Enables the control. This means the control is included in validation
  /// checks and the aggregate value of its parent. Its status recalculates
  /// based on its value and its validators.
  @override
  void markAsEnabled({bool updateParent = true, bool emitEvent = true}) {
    _forEachChild((control) {
      control.markAsEnabled(updateParent: true, emitEvent: emitEvent);
    });
    super.markAsEnabled(updateParent: updateParent, emitEvent: emitEvent);
  }

  /// Insert a new [control] at the [index] position.
  void insert(int index, AbstractControl<T> control) {
    _controls.insert(index, control);
    control.parent = this;
    this.updateValueAndValidity();
    this.emitsCollectionChanged(_controls);
  }

  /// Insert a new [control] at the end of the array.
  void add(AbstractControl<T> control) {
    this.addAll([control]);
  }

  /// Appends all [controls] to the end of this array.
  void addAll(
    Iterable<AbstractControl<T>> controls, {
    bool updateParent,
    bool emitEvent,
  }) {
    _controls.addAll(controls);
    controls.forEach((control) {
      control.parent = this;
    });
    this.updateValueAndValidity(
      updateParent: updateParent,
      emitEvent: emitEvent,
    );
    this.emitsCollectionChanged(_controls);
  }

  /// Removes control at [index]
  void removeAt(int index) {
    final removedControl = _controls.removeAt(index);
    removedControl.parent = null;
    this.updateValueAndValidity();
    this.emitsCollectionChanged(_controls);
  }

  /// Removes [control].
  ///
  /// Throws [FormControlNotFoundException] if no control found.
  void remove(AbstractControl<T> control) {
    final index = _controls.indexOf(control);
    if (index == -1) {
      throw FormControlNotFoundException();
    }
    this.removeAt(index);
  }

  @override
  bool contains(String name) {
    int index = int.tryParse(name);
    if (index != null && index < _controls.length) {
      return true;
    }

    return false;
  }

  /// Retrieves a child control given the control's [name] or path.
  ///
  /// The [name] is a dot-delimited string that represents the index position
  /// of the control in array or the path to the nested control.
  ///
  /// Throws [FormArrayInvalidIndexException] if [name] is not e valid [int]
  /// number.
  ///
  /// Throws [FormControlNotFoundException] if no [FormControl] founded with
  /// the specified [name].
  ///
  /// ### Example:
  ///
  /// ```dart
  /// final array = FormArray([
  ///   FormControl(defaultValue: 'hello'),
  /// ]);
  ///
  /// final control = array.formControl('0');
  ///
  /// print(control.value);
  /// ```
  ///
  /// ```shell
  /// >hello
  /// ```
  ///
  /// Retrieves a nested control
  /// ```dart
  /// final form = FormGroup({
  ///   'address': FormArray([
  ///     FormGroup({
  ///       'zipCode': FormControl<int>(value: 1000),
  ///       'city': FormControl<String>(value: 'Sofia'),
  ///     })
  ///   ]),
  /// });
  ///
  /// form.control('address.0.city');
  /// ```
  @override
  AbstractControl<T> control(String name) {
    final namePath = name.split('.');
    if (namePath.length > 1) {
      final control = this.findControl(namePath);
      if (control != null) {
        return control;
      }
    } else {
      int index = int.tryParse(name);
      if (index == null) {
        throw FormArrayInvalidIndexException(name);
      } else if (index < _controls.length) {
        return _controls[index];
      }
    }

    throw FormControlNotFoundException(controlName: name);
  }

  /// Disposes the array.
  @override
  void dispose() {
    _forEachChild((control) {
      control.parent = null;
      control.dispose();
    });
    this.closeCollectionEvents();
    super.dispose();
  }

  /// Returns true if all children disabled, otherwise returns false.
  ///
  /// This is for internal use only.
  @override
  bool _allControlsDisabled() {
    if (_controls.isEmpty) {
      return false;
    }
    return _controls.every((control) => control.disabled);
  }

  /// Returns true if all children has the specified [status], otherwise
  /// returns false.
  ///
  /// This is for internal use only.
  @override
  bool _anyControlsHaveStatus(ControlStatus status) {
    return _controls.any((control) => control.status == status);
  }

  /// Gets all errors of the array.
  ///
  /// Contains all the errors of the array and the child errors.
  @override
  Map<String, dynamic> get errors {
    final allErrors = Map.of(super.errors);
    _controls.asMap().entries.forEach((entry) {
      final control = entry.value;
      final name = entry.key.toString();
      if (control.enabled && control.hasErrors) {
        allErrors.update(
          name,
          (_) => control.errors,
          ifAbsent: () => control.errors,
        );
      }
    });

    return allErrors;
  }

  @override
  void updateValue(Iterable<T> value, {bool updateParent, bool emitEvent}) {
    for (var i = 0; i < _controls.length; i++) {
      if (value == null || i < value.length) {
        _controls[i].updateValue(
          value == null ? null : value.elementAt(i),
          updateParent: false,
          emitEvent: emitEvent,
        );
      }
    }

    if (value != null && value.length > _controls.length) {
      final newControls = value
          .toList()
          .asMap()
          .entries
          .where((entry) => entry.key >= _controls.length)
          .map((entry) => FormControl<T>(value: entry.value));

      this.addAll(
        newControls,
        updateParent: updateParent,
        emitEvent: emitEvent,
      );
    } else {
      this.updateValueAndValidity(
        updateParent: updateParent,
        emitEvent: emitEvent,
      );
    }
  }

  /// Resets the array, marking all controls as untouched, and setting
  /// a state for children with an initial value and disabled state.
  ///
  /// The [state] is a collection of states for children that resets each
  /// control with an initial value and disabled state.
  ///
  /// ### Reset the values in a form array and the disabled status for the
  /// first control
  /// ````dart
  /// final array = FormArray<String>([
  ///   FormControl<String>(),
  ///   FormControl<String>(),
  /// ]);
  ///
  /// array.resetState([
  ///   ControlState(value: 'name', disabled: true),
  ///   ControlState(value: 'last'),
  /// ]);
  ///
  /// console.log(array.value);  // output: ['name', 'last name']
  /// console.log(array.control('0').disabled);  // output: true
  ///
  /// ```
  void resetState(Iterable<ControlState<T>> state) {
    if (state == null || state.isEmpty) {
      this.reset();
    } else {
      for (var i = 0; i < _controls.length; i++) {
        _controls[i].reset(
          value: i < state.length ? state.elementAt(i)?.value : null,
          disabled: i < state.length ? state.elementAt(i)?.disabled : null,
          updateParent: false,
        );
      }

      _updatePristine();
      this.updateValueAndValidity();
    }
  }

  @override
  void _forEachChild(void Function(AbstractControl) callback) {
    _controls.forEach((control) => callback(control));
  }

  @override
  bool _anyControls(bool Function(AbstractControl) condition) {
    return _controls.any((control) => control.enabled && condition(control));
  }
}
